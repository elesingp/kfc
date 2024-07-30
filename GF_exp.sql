SELECT
 date, 
 ab_test_variant_name,
 impressions, 
 clicks, 
 users,
 purchases, 
 revenue, 
 revenue_per_user,
 aov, 
 ctr, 
 conversion_rate,
 direct_purchases, 
 direct_revenue, 
 recommendations_conversion
FROM (
	WITH '2024-07-30T00:00:00' as first_datetime,
	now() as second_datetime
	SELECT
		toDate(t1.event_datetime) as date,
		t1.ab_test_variant_name as ab_test_variant_name,
		countIf(t1.event_name = 'system_recommendations_showed' and t1.screen_name = 'product_card') as impressions,
    	uniqExact(t2.kiosk_session_id) as clicks,
    	uniqExact(t1.kiosk_session_id) as users,
    	uniqExact(t3.kiosk_session_id, t1.event_name = 'system_order_create_success') as purchases,
    	sumIf(t3.order_value, t1.event_name = 'system_order_create_success')/100 as revenue,
    	revenue / users as revenue_per_user,
    	if(isNaN(avgIf(t3.order_value / 100, t1.event_name = 'system_order_create_success')),
		  NULL,
		  avgIf(t3.order_value / 100, t1.event_name = 'system_order_create_success')) AS aov,
    	clicks / impressions as ctr,
    	purchases / users as conversion_rate,
    	uniqExactIf(t3.kiosk_session_id, t1.kiosk_session_id GLOBAL IN (    
          SELECT 
            kiosk_session_id
          FROM digital_product_analytics.app_metric_events
          WHERE ab_test_name = 'pilot_rec'
          AND event_name = 'system_recommendations_showed' 
          AND screen_name = 'product_card'
        )) as direct_purchases,
	    sumIf(IfNull(t2.price, 0), event_name = 'user_product_added') as direct_revenue,
	    direct_purchases / users as recommendations_conversion
	FROM digital_product_analytics.app_metric_events t1 
	global LEFT JOIN (
	    SELECT
	        kiosk_session_id,
	        event_datetime,
	        prev_ab_test_variant_name as ab_test_variant_name,
	        prev_screen_name as screen_name,
	        source_product,
	        product_id,
	        product_name,
	        product_qnt,
	        price/100 as price
	    FROM (
	        SELECT
		        *,
		        lagInFrame(ab_test_variant_name) OVER(PARTITION BY kiosk_session_id ORDER BY event_datetime) AS prev_ab_test_variant_name,
		        lagInFrame(screen_name) OVER(PARTITION BY kiosk_session_id ORDER BY event_datetime) AS prev_screen_name,
	            lagInFrame(product_name) OVER(partition by kiosk_session_id ORDER BY event_datetime) as source_product,
		        lagInFrame(cat_prod_ids) OVER(PARTITION BY kiosk_session_id ORDER BY event_datetime) AS prev_cat_prod_ids,
		        if(has(prev_cat_prod_ids, product_id) = 1 or has(prev_cat_prod_ids, category_id) = 1, 1, 0) AS has_product_flg
		    FROM (
		    	WITH JSONExtractArrayRaw(recommendations) as rec_arr
			    SELECT
			        kiosk_session_id,
			        event_datetime,
			        ab_test_variant_name,
			        event_name,
			        screen_name,
			        product_id,
			        product_name,
			        category_id,
			        price,
			        product_qnt,
			        arrayConcat(
			            arrayDistinct(arrayMap(x -> JSONExtractString(JSONExtractRaw(x, toString(indexOf(rec_arr, x) - 1)), 'categoryId'), rec_arr)),
			            arrayDistinct(arrayMap(x -> JSONExtractString(JSONExtractRaw(x, toString(indexOf(rec_arr, x) - 1)), 'productId'), rec_arr))
			        ) as cat_prod_ids,
			        countIf(event_name = 'system_recommendations_showed') OVER(partition by kiosk_session_id, product_name) as rec_flg,
			        countIf(event_name = 'system_product_showed') OVER(partition by kiosk_session_id, product_name) as product_show_flg,
			        if(event_name = 'user_product_added' AND rec_flg > 0, false, true) as event_flg
			    FROM digital_product_analytics.app_metric_events
			    WHERE event_datetime BETWEEN first_datetime AND second_datetime
			    AND event_name IN ('user_product_added', 'system_product_showed', 'system_recommendations_showed')
			    AND restaurant_id global IN (
			        SELECT restaurant_id
			        FROM digital_product_analytics.app_metric_events
			        WHERE ab_test_name = 'pilot_rec'
		    	)
	            AND kiosk_session_id != ''
		    )
		    WHERE event_flg = true AND event_name != 'system_product_showed' 
		    )
		    WHERE event_name = 'user_product_added'
		        AND has_product_flg = 1
		        AND prev_screen_name = 'product_card'
		        AND prev_ab_test_variant_name IN ('rostics', 'gravityfield')
		        AND product_show_flg = 0
	) t2 ON t1.kiosk_session_id = t2.kiosk_session_id 
	global LEFT JOIN (
		SELECT 
			kiosk_session_id,
			event_datetime,
			product_qnt,
			order_value 
		FROM digital_product_analytics.app_metric_events
		WHERE ab_test_name = 'pilot_rec' 
		AND event_datetime BETWEEN first_datetime AND second_datetime
		AND kiosk_session_id != ''
		AND event_name = 'system_order_create_success'
	) t3 ON t1.kiosk_session_id = t3.kiosk_session_id AND t1.event_datetime = t3.event_datetime
	WHERE t1.ab_test_name = 'pilot_rec' 
	AND t1.event_datetime BETWEEN first_datetime AND second_datetime
	AND t1.kiosk_session_id != ''
	GROUP BY date, ab_test_variant_name
	ORDER BY date, ab_test_variant_name
) 
