/*Проект первого модуля
* Автор: Дудаков Тимофей Сергеевич
* Дата: 20.05.2025
*/

--Задача 1. Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
data_category AS (
--Определим категории: Санкт-Петербург или ЛенОбласть; активность размещения объявления на продажу
	SELECT 	f.id,
			CASE
				WHEN f.city_id = '6X8I'
				THEN 'Санкт-Петербург'
				ELSE 'ЛенОбл'
			END AS region,
			CASE
				WHEN a.days_exposition::int >= 1 AND a.days_exposition::int <= 30 THEN 'до месяца'
				WHEN a.days_exposition::int >= 31 AND a.days_exposition::int <= 90 THEN 'до трех месяцев'
				WHEN a.days_exposition::int >= 91 AND a.days_exposition::int <= 180 THEN 'до полугода'
				WHEN a.days_exposition::int > 180 THEN 'более полугода'
			END AS ad_activity
	FROM real_estate.flats AS f
	LEFT JOIN real_estate.advertisement AS a ON f.id = a.id
	WHERE f.id IN (SELECT * FROM filtered_id)
		  AND a.days_exposition IS NOT NULL
	),
data_parameters AS (
--Расчитаем необходимые показатели: стоимость 1 кв.метра
	SELECT	f.id,
			a.last_price / f.total_area AS cost_per_meter
	FROM real_estate.flats AS f
	LEFT JOIN real_estate.advertisement AS a ON f.id = a.id
	WHERE f.id IN (SELECT * FROM filtered_id)
		  AND f.type_id = 'F8EM'
	)
--В итоговом запросе выведем все получившиеся данные, а также посчитаем ср. стоимость 1кв.метра, 
--ср.площадь квартиры, медианы количества комнат, балконов, этажей и ср.высоту потолка
SELECT	region,
		ad_activity,
		COUNT(dc.id) AS num_of_ads,
		ROUND(AVG(dp.cost_per_meter)::numeric, 2) AS avg_cpm, --Средняя стоимость за кв.метр
		ROUND(AVG(f.total_area)::numeric, 2) AS avg_area,
		PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.rooms) AS median_rooms,
		PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.balcony) AS median_balcony,
		PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.floor) AS median_floors,
		ROUND(AVG(f.ceiling_height)::numeric, 2) AS avg_ceiling_height
FROM data_category AS dc
LEFT JOIN data_parameters AS dp ON dp.id = dc.id
LEFT JOIN real_estate.flats AS f ON f.id = dc.id 
GROUP BY region, ad_activity; --Сгруппируем по категориям

--Результат:
--region 			ad_activity 	num_of_ads 	avg_cpm 	avg_area 	median_rooms 	median_balcony 	median_floors 	avg_ceiling_height
--ЛенОбл			более полугода	1705		68297.22	52.84		2				1.0				4				2.70
--ЛенОбл			до месяца		862			73275.25	47.86		1				1.0				5				2.70
--ЛенОбл			до полугода		1119		69846.39	50.77		2				1.0				4				2.69
--ЛенОбл			до трех месяцев	1869		67573.43	49.41		2				1.0				4				2.69
--Санкт-Петербург	более полугода	3581		115457.22	66.15		2				1.0				5				2.83
--Санкт-Петербург	до месяца		2168		110568.88	54.38		2				1.0				5				2.76
--Санкт-Петербург	до полугода		2254		111938.92	60.55		2				1.0				5				2.79
--Санкт-Петербург	до трех месяцев	3236		111573.24	56.71		2				1.0				5				2.77
	



--Задача 2. Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
        AND type_id = 'F8EM' -- Добавил фильтр на тип "город"
),
publication_data AS (
-- Извлекаем месяц публикации объявления с дополнительными метриками
    SELECT  EXTRACT(MONTH FROM a.first_day_exposition) AS publication_month,
            COUNT(*) AS publications_count,
            --Добавил подсчет средних для публикаций объявлений
            AVG(a.last_price) AS avg_price_publications,
            AVG(f.total_area) AS avg_area_publications,
            AVG(a.last_price / f.total_area) AS avg_price_per_meter,
            PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.rooms) AS median_rooms,
            PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.balcony) AS median_balcony,
            PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.floor) AS median_floors,
            AVG(f.ceiling_height) AS avg_ceiling_height
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f ON a.id = f.id
    WHERE a.id IN (SELECT * FROM filtered_id)
    GROUP BY publication_month
),
sales_data AS (
-- Рассчитываем месяц продажи (снятия с публикации) с дополнительными метриками
    SELECT  EXTRACT(MONTH FROM a.first_day_exposition + INTERVAL'1 day' * a.days_exposition) AS sales_month,
            COUNT(*) AS sales_count,
            --Добавил подсчет средних для продаж
            AVG(a.last_price) AS avg_price_sales,
            AVG(f.total_area) AS avg_area_sales,
            AVG(a.last_price / f.total_area) AS avg_price_per_meter_sales,
            PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.rooms) AS median_rooms_sales,
            PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.balcony) AS median_balcony_sales,
            PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.floor) AS median_floors_sales,
            AVG(f.ceiling_height) AS avg_ceiling_height_sales
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f ON a.id = f.id
    WHERE a.days_exposition IS NOT NULL 
          AND a.id IN (SELECT * FROM filtered_id)
    GROUP BY sales_month
),
combined_data AS (
-- Объединяем данные о публикациях и продажах                --С учетом дополнения СТЕ срденими значениями
    SELECT  COALESCE(p.publication_month, s.sales_month) AS month_number,
            p.publications_count,
            p.avg_price_publications,
            p.avg_area_publications,
            p.avg_price_per_meter,
            p.median_rooms,
            p.median_balcony,
            p.median_floors,
            p.avg_ceiling_height,
            s.sales_count,
            s.avg_price_sales,
            s.avg_area_sales,
            s.avg_price_per_meter_sales,
            s.median_rooms_sales,
            s.median_balcony_sales,
            s.median_floors_sales,
            s.avg_ceiling_height_sales
    FROM publication_data AS p
    FULL JOIN sales_data AS s ON p.publication_month = s.sales_month
)
-- Итоговый анализ с ранжированием месяцев по активности:
SELECT  month_number,
        CASE
            WHEN month_number = 1 THEN 'Январь'
            WHEN month_number = 2 THEN 'Февраль'
            WHEN month_number = 3 THEN 'Март'
            WHEN month_number = 4 THEN 'Апрель'
            WHEN month_number = 5 THEN 'Май'
            WHEN month_number = 6 THEN 'Июнь'
            WHEN month_number = 7 THEN 'Июль'
            WHEN month_number = 8 THEN 'Август'
            WHEN month_number = 9 THEN 'Сентябрь'
            WHEN month_number = 10 THEN 'Октябрь'
            WHEN month_number = 11 THEN 'Ноябрь'
            WHEN month_number = 12 THEN 'Декабрь'
        END AS month_name,
        publications_count,
        --Добавил в анализ средние значения с округлением до 2х знаков после запятой
        ROUND(avg_price_publications::numeric, 2) AS avg_price_publications,
        ROUND(avg_area_publications::numeric, 2) AS avg_area_publications,
        ROUND(avg_price_per_meter::numeric, 2) AS avg_price_per_meter,
        median_rooms,
        median_balcony,
        median_floors,
        ROUND(avg_ceiling_height::numeric, 2) AS avg_ceiling_height,
        sales_count,
        ROUND(avg_price_sales::numeric, 2) AS avg_price_sales,
        ROUND(avg_area_sales::numeric, 2) AS avg_area_sales,
        ROUND(avg_price_per_meter_sales::numeric, 2) AS avg_price_per_meter_sales,
        median_rooms_sales,
        median_balcony_sales,
        median_floors_sales,
        ROUND(avg_ceiling_height_sales::numeric, 2) AS avg_ceiling_height_sales,
        RANK() OVER (ORDER BY publications_count DESC) AS publication_rank,
        RANK() OVER (ORDER BY sales_count DESC) AS sales_rank
FROM combined_data
ORDER BY month_number;


--Результат:
--month_number	month_name	publications_count	avg_price_publications	avg_area_publications	avg_price_per_meter	median_rooms	median_balcony	median_floors	avg_ceiling_height	sales_count	avg_price_sales	avg_area_sales	avg_price_per_meter_sales	median_rooms_sales 	median_balcony_sales	median_floors_sales	avg_ceiling_height_sales	publication_rank	sales_rank
--1				Январь		1017				6654722.60				58.96					106835.92			2				1.0				4				2.80				1268		6407229.34		57.67			105120.97					2					1.0						4					2.78						11					5
--2				Февраль		1737				6802498.82				60.34					106452.02			2				1.0				4				2.79				1128		6461158.51		60.47			104032.82					2					1.0						4					2.78						1					10
--3				Март		1675				6682126.69				59.41					107320.49			2				1.0				5				2.78				1276		6795332.88		59.45			107554.43					2					1.0						4					2.78						2					4
--4				Апрель		1638				6848816.73				59.97					108450.83			2				1.0				4				2.79				1420		6352050.98		58.23			105892.67					2					1.0						4					2.78						3					1
--5				Май			929					6407810.75				59.20					103510.69			2				0.0				5				2.80				750			5981356.14		57.49			100356.52					2					1.0						5					2.78						12					12
--6				Июнь		1224				6440384.82				58.37					104802.15			2				0.0				5				2.79				782			6416606.75		60.19			101912.78					2					0.0						5					2.78						7					11
--7				Июль		1149				6565639.54				60.42					104488.96			2				1.0				4				2.82				1130		6397169.37		59.04			102505.11					2					0.0						5					2.80						9					9
--8				Август		1166				6690968.80				58.99					107034.70			2				1.0				5				2.78				1145		5928514.41		56.98			100056.84					2					0.0						5					2.77						8					8
--9				Сентябрь	1341				6829994.21				61.04					107563.12			2				1.0				5				2.79				1247		6325893.59		57.75			104397.12					2					1.0						4					2.78						6					6
--10			Октябрь		1437				6464010.32				59.43					104065.11			2				1.0				5				2.76				1367		6333370.20		58.91			104608.70					2					1.0						5					2.77						5					2
--11			Ноябрь		1589				6629812.66				60.03					105468.23			2				1.0				5				2.78				1307		6266124.61		56.87			103882.35					2					1.0						5					2.77						4					3
--12			Декабрь		1112				6921871.18				60.89					106768.32			2				1.0				4				2.81				1179		6499002.06		59.39			105712.63					2					1.0						5					2.79						10					7




--Задача 3. Анализ рынка недвижимости Ленобласти
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
sales_data AS (
 --Соберем необходимые для анализа данные о каждом из городов:
	SELECT 	c.city,
        	COUNT(*) AS total_ads,
        	SUM(CASE 
	        		WHEN a.days_exposition IS NOT NULL THEN 1 
	        		ELSE 0 
	        	END) AS sold_ads,
        	ROUND(SUM(CASE 
	        			WHEN a.days_exposition IS NOT NULL THEN 1 
	        			ELSE 0 
	        	  	  END) * 100.0 / COUNT(*), 2) AS sold_percentage, --Процент проданных
        	ROUND(AVG(a.days_exposition)::numeric, 2) AS avg_days_to_sell,
        	COUNT(DISTINCT f.type_id) AS types_count,
        	ROUND(AVG(f.total_area)::numeric, 2) AS avg_area,
        	ROUND(AVG(a.last_price / f.total_area)::numeric, 2) AS avg_cpm --Средняя стоимость за кв.метр
    FROM real_estate.flats AS f
    LEFT JOIN real_estate.city AS c ON f.city_id = c.city_id
    LEFT JOIN real_estate.advertisement AS a ON f.id = a.id
    WHERE f.city_id != '6X8I' --Исключаем Санкт-Петербург
    GROUP BY c.city
    HAVING COUNT(*) > 50 -- Фильтр по минимальному количеству объявлений
)
--Итоговый запрос, в котором выведем все найденные характеристики и присвоим ранг каждому городу:
SELECT 	city,
    	total_ads,
    	sold_ads,
    	sold_percentage,
    	avg_days_to_sell,
    	types_count,
    	avg_area,
    	avg_cpm,
    	RANK() OVER (ORDER BY sold_ads DESC) AS sales_activity_rank
FROM sales_data
ORDER BY sales_activity_rank;

--Результат:
--city				total_ads	sold_ads	sold_percentage	avg_days_to_sell	types_count	avg_area	avg_cpm		sales_activity_rank
--Мурино			590			551			93.39			148.40				2			44.10		86087.51	1
--Кудрово			472			441			93.43			159.84				2			46.40		95324.93	2
--Шушары			440			408			92.73			156.10				1			53.82		78677.36	3
--Всеволожск		398			339			85.18			197.09				1			56.02		68654.47	4
--Колпино			338			308			91.12			143.60				1			53.23		75424.58	5
--Пушкин			369			307			83.20			209.58				1			61.55		103125.82	6
--Парголово			327			302			92.35			155.50				1			51.52		90175.91	7
--Гатчина			307			268			87.30			189.62				1			50.94		68746.15	8
--Выборг			237			208			87.76			177.38				1			56.15		58141.91	9
--Петергоф			201			176			87.56			204.66				1			51.73		84757.56	10
--Сестрорецк		183			163			89.07			209.31				1			63.37		101757.62	11
--Красное Село		178			158			88.76			192.59				1			54.88		72148.59	12
--Новое Девяткино	144			127			88.19			188.70				1			52.28		76136.76	13
--Сертолово			142			121			85.21			188.45				1			54.03		69356.11	14
--Ломоносов			133			114			85.71			219.41				1			51.18		72724.05	15
--Бугры				114			100			87.72			164.45				1			48.05		80552.21	16
--Кингисепп			104			95			91.35			129.05				1			53.16		46784.12	17
--Тосно				104			94			90.38			160.55				1			54.39		59004.74	18
--Кириши			125			93			74.40			124.28				1			46.74		38875.78	19
--Сланцы			112			91			81.25			167.07				1			48.87		18185.77	20
--Кронштадт			96			87			90.63			168.10				1			52.35		79714.44	21
--Волхов			111			85			76.58			152.40				1			49.66		35087.68	22
--Никольское		94			77			81.91			235.95				2			42.35		57593.31	23
--Коммунар			89			74			83.15			247.30				1			50.14		56740.61	24
--Сосновый Бор		87			74			85.06			99.59				1			52.73		75220.40	24
--Кировск			84			71			84.52			183.97				1			48.94		57574.80	26
--Металлострой		66			61			92.42			158.28				1			51.16		73752.34	27
--Отрадное			80			59			73.75			190.10				1			50.38		57138.29	28
--Янино-1			68			58			85.29			119.00				1			48.97		70595.85	29
--Старая			64			56			87.50			170.50				1			52.84		65299.76	30
--Приозерск			66			51			77.27			235.73				1			49.62		40674.92	31
--Шлиссельбург		57			45			78.95			211.69				1			52.84		58584.10	32
--Луга				56			43			76.79			127.28				1			52.04		41739.75	33
	
	
	