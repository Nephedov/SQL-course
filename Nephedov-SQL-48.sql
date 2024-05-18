-- 1. Какие самолеты имеют более 50 посадочных мест?

  with cte as (
       select aircraft_code,
              count(seat_no)
         from seats
        group by aircraft_code
       having count(seat_no) > 50
       )
select aircraft_code,
       model
  from aircrafts
  join cte using (aircraft_code)
 order by model;
 
-- 2. В каких аэропортах есть рейсы, в рамках которых можно добраться бизнес - классом дешевле, чем эконом - классом? - CTE

-- Мой ответ: В рамках каждого рейса, каждого аэропорта - ни в каких.

with cte1 as (
   select distinct
          flight_id,
          fare_conditions,
          amount as amount_economy
     from ticket_flights tf
    where fare_conditions = 'Economy'
),
     cte2 as (
   select distinct
          flight_id,
          fare_conditions,
          amount as amount_business
     from ticket_flights tf
    where fare_conditions = 'Business'
)
select a.airport_code,
       a.airport_name
  from flights f
  join cte1 c1    on c1.flight_id = f.flight_id
  join cte2 c2    on c2.flight_id = c1.flight_id
  join airports a on a.airport_code = f.departure_airport
 where amount_economy > amount_business
 order by f.flight_id;
 
-- 3. Есть ли самолеты, не имеющие бизнес - класса? -array_agg

select aircraft_code,
       model
  from aircrafts
  join (
	   select aircraft_code,
	          array_agg(fare_conditions) fare
		 from seats
        group by 1
	   )    t using (aircraft_code)
 where fare && array['Business'::varchar] is false;
 
/* 4. Найдите количество занятых мест для каждого рейса,
      процентное отношение количества занятых мест к общему количеству мест в самолете,
      добавьте накопительный итог вывезенных пассажиров по каждому аэропорту на каждый день. - Оконная функция - Подзапрос */

with cte as (
     select distinct
            f.flight_id,
            flight_no,
            departure_airport,
            actual_departure_local,
            count(seat_no)        over (partition by f.flight_id)                          as occupied_seats,
            round((count(seat_no) over (partition by f.flight_id) * 100.0 / all_seats), 2) as occupied_percent
       from flights_v f
       left join boarding_passes bp on bp.flight_id = f.flight_id
       join (
            select aircraft_code,
                   count(seat_no) all_seats
              from seats
             group by 1
             )   s on s.aircraft_code = f.aircraft_code
       where status = 'Arrived'
)
select departure_airport,
       flight_no,
       actual_departure_local,
       occupied_seats,
       occupied_percent,
       sum(occupied_seats) over (partition by departure_airport, date_trunc('day', actual_departure_local::date) order by actual_departure_local) cumulative_total
  from cte;

/* 5. Найдите процентное соотношение перелетов по маршрутам от общего количества перелетов. 
      Выведите в результат названия аэропортов и процентное отношение. - Оконная функция - Оператор ROUND */

with cte1 as (
      select f1.departure_airport,
             f1.arrival_airport,
	         count(f1.flight_id) over (partition by f1.departure_airport, f1.arrival_airport) * 100.0 / count(f1.flight_id) over () all_routes
        from flights f1
)
select distinct
       a1.airport_name departure,
       a2.airport_name arrival,
       round(all_routes, 2) "percent"
  from cte1
  join airports a1 on a1.airport_code = cte1.departure_airport
  join airports a2 on a2.airport_code = cte1.arrival_airport
 group by 1, 2, 3
 order by 1, 2;

-- 6. Выведите количество пассажиров по каждому коду сотового оператора, если учесть, что код оператора - это три символа после +7

--    Не был уверен кто является пассажиром.
--     Тот у кого есть билет:

select substring(contact_data ->> 'phone', 3, 3) operator_number,
       count(*) count_passengers
  from tickets
 group by 1
 order by 1;
 
--     Либо тот у кого на руках уже посадочный билет. И соответственно самолет должен быть уже в воздухе:

select substring(contact_data ->> 'phone', 3, 3) operator_number,
       count(t.passenger_id) count_passengers
  from boarding_passes bp 
  join ticket_flights tf on tf.flight_id = bp.flight_id and tf.ticket_no = bp.ticket_no
  join flights f         on tf.flight_id = f.flight_id 
  join tickets t         on tf.ticket_no = t.ticket_no
 where status = 'Departed'
 group by 1
 order by 1;
 
-- 7. Между какими городами не существует перелетов? - Декартово произведение - Оператор EXCEPT

select r1.departure_city,
       r2.arrival_city
  from routes r1
 cross join (
            select arrival_city
              from routes) r2
 where r1.departure_city > r2.arrival_city
except
select departure_city,
       arrival_city
  from routes;

/* 8. Классифицируйте финансовые обороты (сумма стоимости билетов) по маршрутам:
      До 50 млн - low
      От 50 млн включительно до 150 млн - middle
      От 150 млн включительно - high
      Выведите в результат количество маршрутов в каждом классе. - Оператор CASE */

with cte1 as (
      select case
                  when coalesce(sum(tf.amount), 0) between 0        and 49999999  then 'low'
		          when coalesce(sum(tf.amount), 0) between 50000000 and 149999999 then 'middle'
             else 'high'
             end mark 
		from flights f
		left join ticket_flights tf on tf.flight_id = f.flight_id
	   group by f.departure_airport, f.arrival_airport
)
select mark,
       count(*) count_routes
  from cte1
 group by mark
 order by 2;
 
 -- 9. Выведите пары городов между которыми расстояние более 5000 км - Оператор RADIANS или использование sind/cosd

with cte as (
     select city_a,
            city_b,
            round(acos(sin(latitude_a)*sin(latitude_b) + cos(latitude_a)*cos(latitude_b)*cos(longitude_a - longitude_b)) * 6371) as distance
       from (
		    select a1.city               as city_a,
		           radians(a1.longitude) as longitude_a,
		           radians(a1.latitude)  as latitude_a,
		           a2.city               as city_b,
		           radians(a2.longitude) as longitude_b,
		           radians(a2.latitude)  as latitude_b
		      from airports a1
		     cross join airports a2
		     where a1.city > a2.city ) t
)
select *
  from cte
 where distance > 5000;