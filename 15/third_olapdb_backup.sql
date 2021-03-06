PGDMP                         x            StoragesCUBE    11.7    11.7 �    C           0    0    ENCODING    ENCODING        SET client_encoding = 'UTF8';
                       false            D           0    0 
   STDSTRINGS 
   STDSTRINGS     (   SET standard_conforming_strings = 'on';
                       false            E           0    0 
   SEARCHPATH 
   SEARCHPATH     8   SELECT pg_catalog.set_config('search_path', '', false);
                       false            F           1262    17791    StoragesCUBE    DATABASE     �   CREATE DATABASE "StoragesCUBE" WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'Russian_Russia.1251' LC_CTYPE = 'Russian_Russia.1251';
    DROP DATABASE "StoragesCUBE";
             postgres    false            �            1255    17792    gen_t(integer)    FUNCTION     +  CREATE FUNCTION public.gen_t(n integer) RETURNS TABLE(id integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
i integer;
BEGIN
DROP TABLE IF EXISTS t;
CREATE TEMP TABLE t (
id integer
  );
FOR i IN 1..N LOOP
INSERT INTO t (id) VALUES (i);
END LOOP;
 RETURN QUERY select * from t;
 DROP table t;
END; $$;
 '   DROP FUNCTION public.gen_t(n integer);
       public       postgres    false            �            1255    17793    my_f(date, date)    FUNCTION     �  CREATE FUNCTION public.my_f(d1 date, d2 date) RETURNS TABLE(goods integer, volume numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
  CREATE TEMP TABLE t (
    goods int,
    volume decimal(18,4)
  );

  INSERT INTO t (goods, volume)
  SELECT
    rg.goods,
    rg.volume
  FROM
    recept r JOIN recgoods rg ON r.id=rg.id
  WHERE
    r.ddate BETWEEN d1 AND d2;

  UPDATE
    t
  SET
    volume = 666;

  RETURN QUERY select * from t;
  DROP TABLE t;
END;
$$;
 -   DROP FUNCTION public.my_f(d1 date, d2 date);
       public       postgres    false            �            1255    17794    my_f5(integer)    FUNCTION     P  CREATE FUNCTION public.my_f5(ii integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
  curs CURSOR FOR SELECT
    name,
    region
  FROM
    city where id > ii;
  name text;
  region int;
  i int;
BEGIN

  i = 0;
  FOR r IN curs LOOP
   RAISE NOTICE 'Город: %', r.name;
   i = i + 1;
  END LOOP;

  RETURN i;

END;
$$;
 (   DROP FUNCTION public.my_f5(ii integer);
       public       postgres    false                       1255    17795    remains_actual()    FUNCTION     �  CREATE FUNCTION public.remains_actual() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
	DECLARE
		t_row record;
		cur_rec_volume integer;
		cur_volume integer;
		ids integer[];
		subids integer[];
		rem_ids integer[];
		rem_subids integer[];
    BEGIN
		IF (NEW.price != OLD.price)
			AND (NEW.id = OLD.id)
			AND (NEW.subid = OLD.subid)
			AND (NEW.goods = OLD.goods)
			AND (NEW.volume = OLD.volume)
		THEN
			NEW.price = OLD.price;
            RETURN NEW;
        END IF;
		
	    IF (NEW.id IS NULL) 
			OR (NEW.subid IS NULL) 
			OR (NEW.goods IS NULL)
			OR (NEW.volume IS NULL)
		THEN
            RAISE EXCEPTION 'Column value cannot be null!';
        END IF;
	
		-- Сначала создаем таблицу inc в которой будут все приходы
		-- по данному товару расхода, меньше даты расхода, складу расхода;
		-- считаем, что склад прихода должен соответствовать складу расхода
		-- ============================================
		DROP TABLE IF EXISTS inc;
		CREATE TEMP TABLE inc (
			id integer,
			subid integer,
			goods integer, 
			volume integer,
			ddate date,
			storage integer
		);
		INSERT INTO inc (id, subid, goods, volume, ddate, storage)
		SELECT incgoods.id, incgoods.subid, incgoods.goods, 
			incgoods.volume, income.ddate, income.storage 
		FROM incgoods 
		JOIN income 
		ON income.id=incgoods.id
		JOIN recept ON recept.id=NEW.id
		WHERE income.ddate<recept.ddate
			AND goods=NEW.goods 
			AND income.storage=recept.storage
		ORDER BY ddate DESC; -- LIFO
		-- ============================================
		
		IF ((SELECT sum(volume)-NEW.volume FROM inc)<0) 
		THEN
            RAISE EXCEPTION 'Remains cannot be < 0!';
        END IF;

		cur_rec_volume = NEW.volume;
		FOR t_row IN SELECT * FROM inc LOOP
			cur_volume = t_row.volume - cur_rec_volume;
			IF cur_volume < 0 THEN
				cur_volume = 0;
			END IF;
			cur_rec_volume = cur_rec_volume - t_row.volume;

			INSERT INTO irlink (i_id, i_subid, r_id, r_subid, goods, volume)
			VALUES (t_row.id, t_row.subid, NEW.id, NEW.subid, NEW.goods, (t_row.volume-cur_volume))
			ON CONFLICT (id) 
			DO UPDATE SET volume = (t_row.volume-cur_volume);

			ids = ids || t_row.id;
			subids = subids || t_row.subid;	

			IF cur_volume > 0 THEN
				INSERT INTO remains (id, subid, goods, storage, ddate, volume)
				VALUES (t_row.id, t_row.subid, t_row.goods, t_row.storage, t_row.ddate, cur_volume)
				ON CONFLICT (id, subid) 
				DO UPDATE SET volume = cur_volume;

				rem_ids = rem_ids || t_row.id;
				rem_subids = rem_subids || t_row.subid;	
			END IF;
			EXIT WHEN cur_rec_volume <= 0; 
		END LOOP;
		-- Подчищаем неактуальные записи
		-- не уверен что правильно, но вроде работает
		DELETE FROM irlink WHERE (OLD.id = irlink.r_id)
			AND (OLD.subid = irlink.r_subid)
			AND (OLD.goods = irlink.goods)
			AND NOT(irlink.i_id = ANY(ids))
			AND NOT(irlink.i_subid = ANY(subids));

		DELETE FROM remains WHERE (remains.goods = OLD.goods)
		AND NOT(remains.id = ANY(rem_ids))
		AND NOT(remains.subid = ANY(rem_subids));
		
		DROP TABLE inc;
		RETURN NEW;
    END;
$$;
 '   DROP FUNCTION public.remains_actual();
       public       postgres    false                       1255    17796    sales_trend(date, date)    FUNCTION     �  CREATE FUNCTION public.sales_trend(d_start date, d_end date) RETURNS TABLE(g_group integer, ddate date, predict double precision, eerror double precision)
    LANGUAGE plpgsql
    AS $$
DECLARE
ddate date;
sm double precision;
g_group integer;
alpha integer;
prev_val integer;
prev_group integer;
prev_predict_val integer;
predict_val integer;

ggcur CURSOR FOR
SELECT recept.ddate, sum(recgoods.volume * recgoods.price) AS sm,
goods.g_group FROM goods
JOIN recgoods ON (recgoods.goods = goods.id)
JOIN recept ON (recept.id = recgoods.subid)
WHERE
(recept.ddate >= d_start) AND (recept.ddate <= d_end)
GROUP BY
recept.ddate, goods.g_group
ORDER BY goods.g_group, recept.ddate;

BEGIN
CREATE TEMP TABLE t (
g_group integer,
ddate date,
    predict double precision,
eerror double precision
  );
OPEN ggcur;
prev_group = -666;
alpha = 0.9;
LOOP
FETCH ggcur INTO ddate, sm, g_group;
IF prev_group != g_group THEN
predict_val = alpha*sm;
ELSE
predict_val = alpha*sm+(1-alpha)*prev_predict_val;
END IF;
prev_group = g_group;
prev_predict_val = predict_val;
INSERT INTO t VALUES (g_group, ddate, predict_val, ABS(sm-predict_val));
EXIT WHEN NOT FOUND;
END LOOP;
CLOSE ggcur;
   
   RETURN QUERY select * from t;
   DROP TABLE t;

END; $$;
 <   DROP FUNCTION public.sales_trend(d_start date, d_end date);
       public       postgres    false                       1255    17797    test_sp(date, date) 	   PROCEDURE     �  CREATE PROCEDURE public.test_sp(d1 date, d2 date)
    LANGUAGE plpgsql
    AS $$
BEGIN
  CREATE TEMP TABLE t (
    goods int,
    volume decimal(18,4)
  );
  INSERT INTO t (goods, volume)
  SELECT
    rg.goods,
    rg.volume
  FROM
    recept r JOIN recgoods rg ON r.id=rg.id
  WHERE
    r.ddate BETWEEN d1 AND d2;
UPDATE
    t
  SET
    volume = 666;
RETURN;
  DROP TABLE t;
END;
$$;
 1   DROP PROCEDURE public.test_sp(d1 date, d2 date);
       public       postgres    false            �            1259    17818    city    TABLE     Y   CREATE TABLE public.city (
    id integer NOT NULL,
    name text,
    region integer
);
    DROP TABLE public.city;
       public         postgres    false            �            1259    17824    city_id_seq    SEQUENCE     �   CREATE SEQUENCE public.city_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 "   DROP SEQUENCE public.city_id_seq;
       public       postgres    false    196            G           0    0    city_id_seq    SEQUENCE OWNED BY     ;   ALTER SEQUENCE public.city_id_seq OWNED BY public.city.id;
            public       postgres    false    197            �            1259    17826    client_groups    TABLE     b   CREATE TABLE public.client_groups (
    id integer NOT NULL,
    name text,
    parent integer
);
 !   DROP TABLE public.client_groups;
       public         postgres    false            �            1259    17832    client_groups_id_seq    SEQUENCE     �   CREATE SEQUENCE public.client_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 +   DROP SEQUENCE public.client_groups_id_seq;
       public       postgres    false    198            H           0    0    client_groups_id_seq    SEQUENCE OWNED BY     M   ALTER SEQUENCE public.client_groups_id_seq OWNED BY public.client_groups.id;
            public       postgres    false    199            �            1259    17834    clients    TABLE     �   CREATE TABLE public.clients (
    id integer NOT NULL,
    name text,
    address text,
    city integer,
    client_groups integer
);
    DROP TABLE public.clients;
       public         postgres    false            �            1259    17840    clients_id_seq    SEQUENCE     �   CREATE SEQUENCE public.clients_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 %   DROP SEQUENCE public.clients_id_seq;
       public       postgres    false    200            I           0    0    clients_id_seq    SEQUENCE OWNED BY     A   ALTER SEQUENCE public.clients_id_seq OWNED BY public.clients.id;
            public       postgres    false    201            �            1259    17842    goods    TABLE     �   CREATE TABLE public.goods (
    id integer NOT NULL,
    g_group integer,
    name text,
    weight real,
    length real,
    height real,
    width real
);
    DROP TABLE public.goods;
       public         postgres    false            �            1259    17848    goods_groups    TABLE     a   CREATE TABLE public.goods_groups (
    id integer NOT NULL,
    name text,
    parent integer
);
     DROP TABLE public.goods_groups;
       public         postgres    false            �            1259    17854    goods_groups_id_seq    SEQUENCE     �   CREATE SEQUENCE public.goods_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 *   DROP SEQUENCE public.goods_groups_id_seq;
       public       postgres    false    203            J           0    0    goods_groups_id_seq    SEQUENCE OWNED BY     K   ALTER SEQUENCE public.goods_groups_id_seq OWNED BY public.goods_groups.id;
            public       postgres    false    204            �            1259    17856    goods_id_seq    SEQUENCE     �   CREATE SEQUENCE public.goods_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 #   DROP SEQUENCE public.goods_id_seq;
       public       postgres    false    202            K           0    0    goods_id_seq    SEQUENCE OWNED BY     =   ALTER SEQUENCE public.goods_id_seq OWNED BY public.goods.id;
            public       postgres    false    205            �            1259    17858    incgoods    TABLE     �   CREATE TABLE public.incgoods (
    id integer NOT NULL,
    subid integer NOT NULL,
    goods integer,
    volume integer,
    price integer
);
    DROP TABLE public.incgoods;
       public         postgres    false            �            1259    17861    income    TABLE     �   CREATE TABLE public.income (
    id integer NOT NULL,
    ddate date,
    ndoc integer,
    client integer,
    storage integer
);
    DROP TABLE public.income;
       public         postgres    false            �            1259    17864    income_id_seq    SEQUENCE     �   CREATE SEQUENCE public.income_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE public.income_id_seq;
       public       postgres    false    207            L           0    0    income_id_seq    SEQUENCE OWNED BY     ?   ALTER SEQUENCE public.income_id_seq OWNED BY public.income.id;
            public       postgres    false    208            �            1259    17866    irlink    TABLE     �   CREATE TABLE public.irlink (
    id integer NOT NULL,
    i_id integer,
    i_subid integer,
    r_id integer,
    r_subid integer,
    goods integer,
    volume integer
);
    DROP TABLE public.irlink;
       public         postgres    false            �            1259    17869    irlink_id_seq    SEQUENCE     �   CREATE SEQUENCE public.irlink_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE public.irlink_id_seq;
       public       postgres    false    209            M           0    0    irlink_id_seq    SEQUENCE OWNED BY     ?   ALTER SEQUENCE public.irlink_id_seq OWNED BY public.irlink.id;
            public       postgres    false    210            �            1259    18178    purchase_clients    TABLE     �   CREATE TABLE public.purchase_clients (
    id integer NOT NULL,
    name text NOT NULL,
    address text NOT NULL,
    city integer,
    region integer,
    client_groups integer
);
 $   DROP TABLE public.purchase_clients;
       public         postgres    false            �            1259    18204    purchase_date    TABLE     X   CREATE TABLE public.purchase_date (
    id integer NOT NULL,
    ddate date NOT NULL
);
 !   DROP TABLE public.purchase_date;
       public         postgres    false            �            1259    18202    purchase_date_id_seq    SEQUENCE     �   CREATE SEQUENCE public.purchase_date_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 +   DROP SEQUENCE public.purchase_date_id_seq;
       public       postgres    false    228            N           0    0    purchase_date_id_seq    SEQUENCE OWNED BY     M   ALTER SEQUENCE public.purchase_date_id_seq OWNED BY public.purchase_date.id;
            public       postgres    false    227            �            1259    18278    purchase_fact_table    TABLE     �   CREATE TABLE public.purchase_fact_table (
    id integer NOT NULL,
    amount real,
    quantity integer,
    volume real,
    weight real,
    ddate_id integer,
    client_id integer,
    storage_id integer,
    goods_id integer
);
 '   DROP TABLE public.purchase_fact_table;
       public         postgres    false            �            1259    18276    purchase_fact_table_id_seq    SEQUENCE     �   CREATE SEQUENCE public.purchase_fact_table_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 1   DROP SEQUENCE public.purchase_fact_table_id_seq;
       public       postgres    false    241            O           0    0    purchase_fact_table_id_seq    SEQUENCE OWNED BY     Y   ALTER SEQUENCE public.purchase_fact_table_id_seq OWNED BY public.purchase_fact_table.id;
            public       postgres    false    240            �            1259    18259    purchase_goods    TABLE     �   CREATE TABLE public.purchase_goods (
    id integer NOT NULL,
    name text NOT NULL,
    g_group integer,
    weight real,
    length real,
    height real,
    width real,
    vol real
);
 "   DROP TABLE public.purchase_goods;
       public         postgres    false            �            1259    18257    purchase_goods_id_seq    SEQUENCE     �   CREATE SEQUENCE public.purchase_goods_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 ,   DROP SEQUENCE public.purchase_goods_id_seq;
       public       postgres    false    238            P           0    0    purchase_goods_id_seq    SEQUENCE OWNED BY     O   ALTER SEQUENCE public.purchase_goods_id_seq OWNED BY public.purchase_goods.id;
            public       postgres    false    237            �            1259    18226    purchase_storage    TABLE     n   CREATE TABLE public.purchase_storage (
    id integer NOT NULL,
    name text NOT NULL,
    active integer
);
 $   DROP TABLE public.purchase_storage;
       public         postgres    false            �            1259    18224    purchase_storage_id_seq    SEQUENCE     �   CREATE SEQUENCE public.purchase_storage_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 .   DROP SEQUENCE public.purchase_storage_id_seq;
       public       postgres    false    232            Q           0    0    purchase_storage_id_seq    SEQUENCE OWNED BY     S   ALTER SEQUENCE public.purchase_storage_id_seq OWNED BY public.purchase_storage.id;
            public       postgres    false    231            �            1259    17871    recept    TABLE     �   CREATE TABLE public.recept (
    id integer NOT NULL,
    ddate date,
    ndoc integer,
    client integer,
    storage integer
);
    DROP TABLE public.recept;
       public         postgres    false            �            1259    17874    recept_id_seq    SEQUENCE     �   CREATE SEQUENCE public.recept_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE public.recept_id_seq;
       public       postgres    false    211            R           0    0    recept_id_seq    SEQUENCE OWNED BY     ?   ALTER SEQUENCE public.recept_id_seq OWNED BY public.recept.id;
            public       postgres    false    212            �            1259    17876    recgoods    TABLE     �   CREATE TABLE public.recgoods (
    id integer NOT NULL,
    subid integer NOT NULL,
    goods integer,
    volume integer,
    price real
);
    DROP TABLE public.recgoods;
       public         postgres    false            �            1259    17879    region    TABLE     G   CREATE TABLE public.region (
    id integer NOT NULL,
    name text
);
    DROP TABLE public.region;
       public         postgres    false            �            1259    17885    region_id_seq    SEQUENCE     �   CREATE SEQUENCE public.region_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE public.region_id_seq;
       public       postgres    false    214            S           0    0    region_id_seq    SEQUENCE OWNED BY     ?   ALTER SEQUENCE public.region_id_seq OWNED BY public.region.id;
            public       postgres    false    215            �            1259    17887    remains    TABLE     �   CREATE TABLE public.remains (
    id integer NOT NULL,
    subid integer NOT NULL,
    goods integer,
    storage integer,
    ddate date,
    volume integer
);
    DROP TABLE public.remains;
       public         postgres    false            �            1259    18196    remains_date    TABLE     W   CREATE TABLE public.remains_date (
    id integer NOT NULL,
    ddate date NOT NULL
);
     DROP TABLE public.remains_date;
       public         postgres    false            �            1259    18194    remains_date_id_seq    SEQUENCE     �   CREATE SEQUENCE public.remains_date_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 *   DROP SEQUENCE public.remains_date_id_seq;
       public       postgres    false    226            T           0    0    remains_date_id_seq    SEQUENCE OWNED BY     K   ALTER SEQUENCE public.remains_date_id_seq OWNED BY public.remains_date.id;
            public       postgres    false    225            �            1259    18308    remains_fact_table    TABLE     �   CREATE TABLE public.remains_fact_table (
    id integer NOT NULL,
    amount real,
    quantity integer,
    volume real,
    weight real,
    ddate_id integer,
    storage_id integer,
    goods_id integer
);
 &   DROP TABLE public.remains_fact_table;
       public         postgres    false            �            1259    18306    remains_fact_table_id_seq    SEQUENCE     �   CREATE SEQUENCE public.remains_fact_table_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 0   DROP SEQUENCE public.remains_fact_table_id_seq;
       public       postgres    false    243            U           0    0    remains_fact_table_id_seq    SEQUENCE OWNED BY     W   ALTER SEQUENCE public.remains_fact_table_id_seq OWNED BY public.remains_fact_table.id;
            public       postgres    false    242            �            1259    18268    remains_goods    TABLE     �   CREATE TABLE public.remains_goods (
    id integer NOT NULL,
    name text NOT NULL,
    g_group integer,
    weight real,
    length real,
    height real,
    width real,
    vol real
);
 !   DROP TABLE public.remains_goods;
       public         postgres    false            �            1259    18237    remains_storage    TABLE     m   CREATE TABLE public.remains_storage (
    id integer NOT NULL,
    name text NOT NULL,
    active integer
);
 #   DROP TABLE public.remains_storage;
       public         postgres    false            �            1259    18235    remains_storage_id_seq    SEQUENCE     �   CREATE SEQUENCE public.remains_storage_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 -   DROP SEQUENCE public.remains_storage_id_seq;
       public       postgres    false    234            V           0    0    remains_storage_id_seq    SEQUENCE OWNED BY     Q   ALTER SEQUENCE public.remains_storage_id_seq OWNED BY public.remains_storage.id;
            public       postgres    false    233            �            1259    18170    sales_clients    TABLE     �   CREATE TABLE public.sales_clients (
    id integer NOT NULL,
    name text NOT NULL,
    address text NOT NULL,
    city integer,
    region integer,
    client_groups integer
);
 !   DROP TABLE public.sales_clients;
       public         postgres    false            �            1259    18188 
   sales_date    TABLE     U   CREATE TABLE public.sales_date (
    id integer NOT NULL,
    ddate date NOT NULL
);
    DROP TABLE public.sales_date;
       public         postgres    false            �            1259    18186    sales_date_id_seq    SEQUENCE     �   CREATE SEQUENCE public.sales_date_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 (   DROP SEQUENCE public.sales_date_id_seq;
       public       postgres    false    224            W           0    0    sales_date_id_seq    SEQUENCE OWNED BY     G   ALTER SEQUENCE public.sales_date_id_seq OWNED BY public.sales_date.id;
            public       postgres    false    223            �            1259    18331    sales_fact_table    TABLE     �   CREATE TABLE public.sales_fact_table (
    id integer NOT NULL,
    amount real,
    quantity integer,
    volume real,
    weight real,
    cost_price real,
    ddate_id integer,
    client_id integer,
    storage_id integer,
    goods_id integer
);
 $   DROP TABLE public.sales_fact_table;
       public         postgres    false            �            1259    18329    sales_fact_table_id_seq    SEQUENCE     �   CREATE SEQUENCE public.sales_fact_table_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 .   DROP SEQUENCE public.sales_fact_table_id_seq;
       public       postgres    false    245            X           0    0    sales_fact_table_id_seq    SEQUENCE OWNED BY     S   ALTER SEQUENCE public.sales_fact_table_id_seq OWNED BY public.sales_fact_table.id;
            public       postgres    false    244            �            1259    18248    sales_goods    TABLE     �   CREATE TABLE public.sales_goods (
    id integer NOT NULL,
    name text NOT NULL,
    g_group integer,
    weight real,
    length real,
    height real,
    width real,
    vol real
);
    DROP TABLE public.sales_goods;
       public         postgres    false            �            1259    18246    sales_goods_id_seq    SEQUENCE     �   CREATE SEQUENCE public.sales_goods_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 )   DROP SEQUENCE public.sales_goods_id_seq;
       public       postgres    false    236            Y           0    0    sales_goods_id_seq    SEQUENCE OWNED BY     I   ALTER SEQUENCE public.sales_goods_id_seq OWNED BY public.sales_goods.id;
            public       postgres    false    235            �            1259    18214    sales_storage    TABLE     k   CREATE TABLE public.sales_storage (
    id integer NOT NULL,
    name text NOT NULL,
    active integer
);
 !   DROP TABLE public.sales_storage;
       public         postgres    false            �            1259    18212    sales_storage_id_seq    SEQUENCE     �   CREATE SEQUENCE public.sales_storage_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 +   DROP SEQUENCE public.sales_storage_id_seq;
       public       postgres    false    230            Z           0    0    sales_storage_id_seq    SEQUENCE OWNED BY     M   ALTER SEQUENCE public.sales_storage_id_seq OWNED BY public.sales_storage.id;
            public       postgres    false    229            �            1259    17890    storages    TABLE     ]   CREATE TABLE public.storages (
    id integer NOT NULL,
    name text,
    active integer
);
    DROP TABLE public.storages;
       public         postgres    false            �            1259    17896    storages_id_seq    SEQUENCE     �   CREATE SEQUENCE public.storages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 &   DROP SEQUENCE public.storages_id_seq;
       public       postgres    false    217            [           0    0    storages_id_seq    SEQUENCE OWNED BY     C   ALTER SEQUENCE public.storages_id_seq OWNED BY public.storages.id;
            public       postgres    false    218            �            1259    17898    supply    TABLE     �   CREATE TABLE public.supply (
    id integer NOT NULL,
    storage integer,
    ddate date,
    summ integer,
    volume integer,
    cnt integer
);
    DROP TABLE public.supply;
       public         postgres    false            �            1259    17901    supply_id_seq    SEQUENCE     �   CREATE SEQUENCE public.supply_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE public.supply_id_seq;
       public       postgres    false    219            \           0    0    supply_id_seq    SEQUENCE OWNED BY     ?   ALTER SEQUENCE public.supply_id_seq OWNED BY public.supply.id;
            public       postgres    false    220            (           2604    17910    city id    DEFAULT     b   ALTER TABLE ONLY public.city ALTER COLUMN id SET DEFAULT nextval('public.city_id_seq'::regclass);
 6   ALTER TABLE public.city ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    197    196            )           2604    17911    client_groups id    DEFAULT     t   ALTER TABLE ONLY public.client_groups ALTER COLUMN id SET DEFAULT nextval('public.client_groups_id_seq'::regclass);
 ?   ALTER TABLE public.client_groups ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    199    198            *           2604    17912 
   clients id    DEFAULT     h   ALTER TABLE ONLY public.clients ALTER COLUMN id SET DEFAULT nextval('public.clients_id_seq'::regclass);
 9   ALTER TABLE public.clients ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    201    200            +           2604    17913    goods id    DEFAULT     d   ALTER TABLE ONLY public.goods ALTER COLUMN id SET DEFAULT nextval('public.goods_id_seq'::regclass);
 7   ALTER TABLE public.goods ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    205    202            ,           2604    17914    goods_groups id    DEFAULT     r   ALTER TABLE ONLY public.goods_groups ALTER COLUMN id SET DEFAULT nextval('public.goods_groups_id_seq'::regclass);
 >   ALTER TABLE public.goods_groups ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    204    203            -           2604    17915 	   income id    DEFAULT     f   ALTER TABLE ONLY public.income ALTER COLUMN id SET DEFAULT nextval('public.income_id_seq'::regclass);
 8   ALTER TABLE public.income ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    208    207            .           2604    17916 	   irlink id    DEFAULT     f   ALTER TABLE ONLY public.irlink ALTER COLUMN id SET DEFAULT nextval('public.irlink_id_seq'::regclass);
 8   ALTER TABLE public.irlink ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    210    209            5           2604    18207    purchase_date id    DEFAULT     t   ALTER TABLE ONLY public.purchase_date ALTER COLUMN id SET DEFAULT nextval('public.purchase_date_id_seq'::regclass);
 ?   ALTER TABLE public.purchase_date ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    228    227    228            ;           2604    18281    purchase_fact_table id    DEFAULT     �   ALTER TABLE ONLY public.purchase_fact_table ALTER COLUMN id SET DEFAULT nextval('public.purchase_fact_table_id_seq'::regclass);
 E   ALTER TABLE public.purchase_fact_table ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    241    240    241            :           2604    18262    purchase_goods id    DEFAULT     v   ALTER TABLE ONLY public.purchase_goods ALTER COLUMN id SET DEFAULT nextval('public.purchase_goods_id_seq'::regclass);
 @   ALTER TABLE public.purchase_goods ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    237    238    238            7           2604    18229    purchase_storage id    DEFAULT     z   ALTER TABLE ONLY public.purchase_storage ALTER COLUMN id SET DEFAULT nextval('public.purchase_storage_id_seq'::regclass);
 B   ALTER TABLE public.purchase_storage ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    232    231    232            /           2604    17917 	   recept id    DEFAULT     f   ALTER TABLE ONLY public.recept ALTER COLUMN id SET DEFAULT nextval('public.recept_id_seq'::regclass);
 8   ALTER TABLE public.recept ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    212    211            0           2604    17918 	   region id    DEFAULT     f   ALTER TABLE ONLY public.region ALTER COLUMN id SET DEFAULT nextval('public.region_id_seq'::regclass);
 8   ALTER TABLE public.region ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    215    214            4           2604    18199    remains_date id    DEFAULT     r   ALTER TABLE ONLY public.remains_date ALTER COLUMN id SET DEFAULT nextval('public.remains_date_id_seq'::regclass);
 >   ALTER TABLE public.remains_date ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    225    226    226            <           2604    18311    remains_fact_table id    DEFAULT     ~   ALTER TABLE ONLY public.remains_fact_table ALTER COLUMN id SET DEFAULT nextval('public.remains_fact_table_id_seq'::regclass);
 D   ALTER TABLE public.remains_fact_table ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    243    242    243            8           2604    18240    remains_storage id    DEFAULT     x   ALTER TABLE ONLY public.remains_storage ALTER COLUMN id SET DEFAULT nextval('public.remains_storage_id_seq'::regclass);
 A   ALTER TABLE public.remains_storage ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    234    233    234            3           2604    18191    sales_date id    DEFAULT     n   ALTER TABLE ONLY public.sales_date ALTER COLUMN id SET DEFAULT nextval('public.sales_date_id_seq'::regclass);
 <   ALTER TABLE public.sales_date ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    224    223    224            =           2604    18334    sales_fact_table id    DEFAULT     z   ALTER TABLE ONLY public.sales_fact_table ALTER COLUMN id SET DEFAULT nextval('public.sales_fact_table_id_seq'::regclass);
 B   ALTER TABLE public.sales_fact_table ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    245    244    245            9           2604    18251    sales_goods id    DEFAULT     p   ALTER TABLE ONLY public.sales_goods ALTER COLUMN id SET DEFAULT nextval('public.sales_goods_id_seq'::regclass);
 =   ALTER TABLE public.sales_goods ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    235    236    236            6           2604    18217    sales_storage id    DEFAULT     t   ALTER TABLE ONLY public.sales_storage ALTER COLUMN id SET DEFAULT nextval('public.sales_storage_id_seq'::regclass);
 ?   ALTER TABLE public.sales_storage ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    229    230    230            1           2604    17919    storages id    DEFAULT     j   ALTER TABLE ONLY public.storages ALTER COLUMN id SET DEFAULT nextval('public.storages_id_seq'::regclass);
 :   ALTER TABLE public.storages ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    218    217            2           2604    17920 	   supply id    DEFAULT     f   ALTER TABLE ONLY public.supply ALTER COLUMN id SET DEFAULT nextval('public.supply_id_seq'::regclass);
 8   ALTER TABLE public.supply ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    220    219                      0    17818    city 
   TABLE DATA               0   COPY public.city (id, name, region) FROM stdin;
    public       postgres    false    196   �                0    17826    client_groups 
   TABLE DATA               9   COPY public.client_groups (id, name, parent) FROM stdin;
    public       postgres    false    198                   0    17834    clients 
   TABLE DATA               I   COPY public.clients (id, name, address, city, client_groups) FROM stdin;
    public       postgres    false    200   �                0    17842    goods 
   TABLE DATA               Q   COPY public.goods (id, g_group, name, weight, length, height, width) FROM stdin;
    public       postgres    false    202   �	                0    17848    goods_groups 
   TABLE DATA               8   COPY public.goods_groups (id, name, parent) FROM stdin;
    public       postgres    false    203   �
                0    17858    incgoods 
   TABLE DATA               C   COPY public.incgoods (id, subid, goods, volume, price) FROM stdin;
    public       postgres    false    206   4                0    17861    income 
   TABLE DATA               B   COPY public.income (id, ddate, ndoc, client, storage) FROM stdin;
    public       postgres    false    207   �                0    17866    irlink 
   TABLE DATA               Q   COPY public.irlink (id, i_id, i_subid, r_id, r_subid, goods, volume) FROM stdin;
    public       postgres    false    209   �      )          0    18178    purchase_clients 
   TABLE DATA               Z   COPY public.purchase_clients (id, name, address, city, region, client_groups) FROM stdin;
    public       postgres    false    222         /          0    18204    purchase_date 
   TABLE DATA               2   COPY public.purchase_date (id, ddate) FROM stdin;
    public       postgres    false    228   �      <          0    18278    purchase_fact_table 
   TABLE DATA               ~   COPY public.purchase_fact_table (id, amount, quantity, volume, weight, ddate_id, client_id, storage_id, goods_id) FROM stdin;
    public       postgres    false    241   4      9          0    18259    purchase_goods 
   TABLE DATA               _   COPY public.purchase_goods (id, name, g_group, weight, length, height, width, vol) FROM stdin;
    public       postgres    false    238   �      3          0    18226    purchase_storage 
   TABLE DATA               <   COPY public.purchase_storage (id, name, active) FROM stdin;
    public       postgres    false    232   4                0    17871    recept 
   TABLE DATA               B   COPY public.recept (id, ddate, ndoc, client, storage) FROM stdin;
    public       postgres    false    211                    0    17876    recgoods 
   TABLE DATA               C   COPY public.recgoods (id, subid, goods, volume, price) FROM stdin;
    public       postgres    false    213   �      !          0    17879    region 
   TABLE DATA               *   COPY public.region (id, name) FROM stdin;
    public       postgres    false    214   '      #          0    17887    remains 
   TABLE DATA               K   COPY public.remains (id, subid, goods, storage, ddate, volume) FROM stdin;
    public       postgres    false    216   �      -          0    18196    remains_date 
   TABLE DATA               1   COPY public.remains_date (id, ddate) FROM stdin;
    public       postgres    false    226   �      >          0    18308    remains_fact_table 
   TABLE DATA               r   COPY public.remains_fact_table (id, amount, quantity, volume, weight, ddate_id, storage_id, goods_id) FROM stdin;
    public       postgres    false    243   !      :          0    18268    remains_goods 
   TABLE DATA               ^   COPY public.remains_goods (id, name, g_group, weight, length, height, width, vol) FROM stdin;
    public       postgres    false    239   O      5          0    18237    remains_storage 
   TABLE DATA               ;   COPY public.remains_storage (id, name, active) FROM stdin;
    public       postgres    false    234   �      (          0    18170    sales_clients 
   TABLE DATA               W   COPY public.sales_clients (id, name, address, city, region, client_groups) FROM stdin;
    public       postgres    false    221   �      +          0    18188 
   sales_date 
   TABLE DATA               /   COPY public.sales_date (id, ddate) FROM stdin;
    public       postgres    false    224   �      @          0    18331    sales_fact_table 
   TABLE DATA               �   COPY public.sales_fact_table (id, amount, quantity, volume, weight, cost_price, ddate_id, client_id, storage_id, goods_id) FROM stdin;
    public       postgres    false    245   �      7          0    18248    sales_goods 
   TABLE DATA               \   COPY public.sales_goods (id, name, g_group, weight, length, height, width, vol) FROM stdin;
    public       postgres    false    236   l      1          0    18214    sales_storage 
   TABLE DATA               9   COPY public.sales_storage (id, name, active) FROM stdin;
    public       postgres    false    230   T      $          0    17890    storages 
   TABLE DATA               4   COPY public.storages (id, name, active) FROM stdin;
    public       postgres    false    217   �      &          0    17898    supply 
   TABLE DATA               G   COPY public.supply (id, storage, ddate, summ, volume, cnt) FROM stdin;
    public       postgres    false    219   T      ]           0    0    city_id_seq    SEQUENCE SET     ;   SELECT pg_catalog.setval('public.city_id_seq', 106, true);
            public       postgres    false    197            ^           0    0    client_groups_id_seq    SEQUENCE SET     C   SELECT pg_catalog.setval('public.client_groups_id_seq', 1, false);
            public       postgres    false    199            _           0    0    clients_id_seq    SEQUENCE SET     =   SELECT pg_catalog.setval('public.clients_id_seq', 1, false);
            public       postgres    false    201            `           0    0    goods_groups_id_seq    SEQUENCE SET     B   SELECT pg_catalog.setval('public.goods_groups_id_seq', 1, false);
            public       postgres    false    204            a           0    0    goods_id_seq    SEQUENCE SET     ;   SELECT pg_catalog.setval('public.goods_id_seq', 1, false);
            public       postgres    false    205            b           0    0    income_id_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('public.income_id_seq', 1, false);
            public       postgres    false    208            c           0    0    irlink_id_seq    SEQUENCE SET     ;   SELECT pg_catalog.setval('public.irlink_id_seq', 6, true);
            public       postgres    false    210            d           0    0    purchase_date_id_seq    SEQUENCE SET     B   SELECT pg_catalog.setval('public.purchase_date_id_seq', 8, true);
            public       postgres    false    227            e           0    0    purchase_fact_table_id_seq    SEQUENCE SET     H   SELECT pg_catalog.setval('public.purchase_fact_table_id_seq', 9, true);
            public       postgres    false    240            f           0    0    purchase_goods_id_seq    SEQUENCE SET     D   SELECT pg_catalog.setval('public.purchase_goods_id_seq', 1, false);
            public       postgres    false    237            g           0    0    purchase_storage_id_seq    SEQUENCE SET     E   SELECT pg_catalog.setval('public.purchase_storage_id_seq', 1, true);
            public       postgres    false    231            h           0    0    recept_id_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('public.recept_id_seq', 1, false);
            public       postgres    false    212            i           0    0    region_id_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('public.region_id_seq', 1, false);
            public       postgres    false    215            j           0    0    remains_date_id_seq    SEQUENCE SET     A   SELECT pg_catalog.setval('public.remains_date_id_seq', 2, true);
            public       postgres    false    225            k           0    0    remains_fact_table_id_seq    SEQUENCE SET     G   SELECT pg_catalog.setval('public.remains_fact_table_id_seq', 1, true);
            public       postgres    false    242            l           0    0    remains_storage_id_seq    SEQUENCE SET     D   SELECT pg_catalog.setval('public.remains_storage_id_seq', 1, true);
            public       postgres    false    233            m           0    0    sales_date_id_seq    SEQUENCE SET     ?   SELECT pg_catalog.setval('public.sales_date_id_seq', 7, true);
            public       postgres    false    223            n           0    0    sales_fact_table_id_seq    SEQUENCE SET     E   SELECT pg_catalog.setval('public.sales_fact_table_id_seq', 6, true);
            public       postgres    false    244            o           0    0    sales_goods_id_seq    SEQUENCE SET     A   SELECT pg_catalog.setval('public.sales_goods_id_seq', 1, false);
            public       postgres    false    235            p           0    0    sales_storage_id_seq    SEQUENCE SET     B   SELECT pg_catalog.setval('public.sales_storage_id_seq', 5, true);
            public       postgres    false    229            q           0    0    storages_id_seq    SEQUENCE SET     =   SELECT pg_catalog.setval('public.storages_id_seq', 3, true);
            public       postgres    false    218            r           0    0    supply_id_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('public.supply_id_seq', 10, true);
            public       postgres    false    220            ?           2606    17930    city city_pkey 
   CONSTRAINT     L   ALTER TABLE ONLY public.city
    ADD CONSTRAINT city_pkey PRIMARY KEY (id);
 8   ALTER TABLE ONLY public.city DROP CONSTRAINT city_pkey;
       public         postgres    false    196            A           2606    17932     client_groups client_groups_pkey 
   CONSTRAINT     ^   ALTER TABLE ONLY public.client_groups
    ADD CONSTRAINT client_groups_pkey PRIMARY KEY (id);
 J   ALTER TABLE ONLY public.client_groups DROP CONSTRAINT client_groups_pkey;
       public         postgres    false    198            C           2606    17934    clients clients_pkey 
   CONSTRAINT     R   ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);
 >   ALTER TABLE ONLY public.clients DROP CONSTRAINT clients_pkey;
       public         postgres    false    200            G           2606    17936    goods_groups goods_groups_pkey 
   CONSTRAINT     \   ALTER TABLE ONLY public.goods_groups
    ADD CONSTRAINT goods_groups_pkey PRIMARY KEY (id);
 H   ALTER TABLE ONLY public.goods_groups DROP CONSTRAINT goods_groups_pkey;
       public         postgres    false    203            E           2606    17938    goods goods_pkey 
   CONSTRAINT     N   ALTER TABLE ONLY public.goods
    ADD CONSTRAINT goods_pkey PRIMARY KEY (id);
 :   ALTER TABLE ONLY public.goods DROP CONSTRAINT goods_pkey;
       public         postgres    false    202            I           2606    17940    incgoods incgoods_pkey 
   CONSTRAINT     [   ALTER TABLE ONLY public.incgoods
    ADD CONSTRAINT incgoods_pkey PRIMARY KEY (id, subid);
 @   ALTER TABLE ONLY public.incgoods DROP CONSTRAINT incgoods_pkey;
       public         postgres    false    206    206            K           2606    17942    income income_pkey 
   CONSTRAINT     P   ALTER TABLE ONLY public.income
    ADD CONSTRAINT income_pkey PRIMARY KEY (id);
 <   ALTER TABLE ONLY public.income DROP CONSTRAINT income_pkey;
       public         postgres    false    207            M           2606    17944    irlink irlink_pkey 
   CONSTRAINT     P   ALTER TABLE ONLY public.irlink
    ADD CONSTRAINT irlink_pkey PRIMARY KEY (id);
 <   ALTER TABLE ONLY public.irlink DROP CONSTRAINT irlink_pkey;
       public         postgres    false    209            q           2606    18283 ,   purchase_fact_table purchase_fact_table_pkey 
   CONSTRAINT     j   ALTER TABLE ONLY public.purchase_fact_table
    ADD CONSTRAINT purchase_fact_table_pkey PRIMARY KEY (id);
 V   ALTER TABLE ONLY public.purchase_fact_table DROP CONSTRAINT purchase_fact_table_pkey;
       public         postgres    false    241            ]           2606    18185 %   purchase_clients purchaseclients_pkey 
   CONSTRAINT     c   ALTER TABLE ONLY public.purchase_clients
    ADD CONSTRAINT purchaseclients_pkey PRIMARY KEY (id);
 O   ALTER TABLE ONLY public.purchase_clients DROP CONSTRAINT purchaseclients_pkey;
       public         postgres    false    222            c           2606    18209    purchase_date purchasedate_pkey 
   CONSTRAINT     ]   ALTER TABLE ONLY public.purchase_date
    ADD CONSTRAINT purchasedate_pkey PRIMARY KEY (id);
 I   ALTER TABLE ONLY public.purchase_date DROP CONSTRAINT purchasedate_pkey;
       public         postgres    false    228            m           2606    18267 !   purchase_goods purchasegoods_pkey 
   CONSTRAINT     _   ALTER TABLE ONLY public.purchase_goods
    ADD CONSTRAINT purchasegoods_pkey PRIMARY KEY (id);
 K   ALTER TABLE ONLY public.purchase_goods DROP CONSTRAINT purchasegoods_pkey;
       public         postgres    false    238            g           2606    18234 %   purchase_storage purchasestorage_pkey 
   CONSTRAINT     c   ALTER TABLE ONLY public.purchase_storage
    ADD CONSTRAINT purchasestorage_pkey PRIMARY KEY (id);
 O   ALTER TABLE ONLY public.purchase_storage DROP CONSTRAINT purchasestorage_pkey;
       public         postgres    false    232            O           2606    17946    recept recept_pkey 
   CONSTRAINT     P   ALTER TABLE ONLY public.recept
    ADD CONSTRAINT recept_pkey PRIMARY KEY (id);
 <   ALTER TABLE ONLY public.recept DROP CONSTRAINT recept_pkey;
       public         postgres    false    211            Q           2606    17948    recgoods recgoods_pkey 
   CONSTRAINT     [   ALTER TABLE ONLY public.recgoods
    ADD CONSTRAINT recgoods_pkey PRIMARY KEY (id, subid);
 @   ALTER TABLE ONLY public.recgoods DROP CONSTRAINT recgoods_pkey;
       public         postgres    false    213    213            S           2606    17950    region region_pkey 
   CONSTRAINT     P   ALTER TABLE ONLY public.region
    ADD CONSTRAINT region_pkey PRIMARY KEY (id);
 <   ALTER TABLE ONLY public.region DROP CONSTRAINT region_pkey;
       public         postgres    false    214            s           2606    18313 *   remains_fact_table remains_fact_table_pkey 
   CONSTRAINT     h   ALTER TABLE ONLY public.remains_fact_table
    ADD CONSTRAINT remains_fact_table_pkey PRIMARY KEY (id);
 T   ALTER TABLE ONLY public.remains_fact_table DROP CONSTRAINT remains_fact_table_pkey;
       public         postgres    false    243            U           2606    17952    remains remains_pkey 
   CONSTRAINT     Y   ALTER TABLE ONLY public.remains
    ADD CONSTRAINT remains_pkey PRIMARY KEY (id, subid);
 >   ALTER TABLE ONLY public.remains DROP CONSTRAINT remains_pkey;
       public         postgres    false    216    216            a           2606    18201    remains_date remainsdate_pkey 
   CONSTRAINT     [   ALTER TABLE ONLY public.remains_date
    ADD CONSTRAINT remainsdate_pkey PRIMARY KEY (id);
 G   ALTER TABLE ONLY public.remains_date DROP CONSTRAINT remainsdate_pkey;
       public         postgres    false    226            o           2606    18275    remains_goods remainsgoods_pkey 
   CONSTRAINT     ]   ALTER TABLE ONLY public.remains_goods
    ADD CONSTRAINT remainsgoods_pkey PRIMARY KEY (id);
 I   ALTER TABLE ONLY public.remains_goods DROP CONSTRAINT remainsgoods_pkey;
       public         postgres    false    239            i           2606    18245 #   remains_storage remainsstorage_pkey 
   CONSTRAINT     a   ALTER TABLE ONLY public.remains_storage
    ADD CONSTRAINT remainsstorage_pkey PRIMARY KEY (id);
 M   ALTER TABLE ONLY public.remains_storage DROP CONSTRAINT remainsstorage_pkey;
       public         postgres    false    234            u           2606    18336 &   sales_fact_table sales_fact_table_pkey 
   CONSTRAINT     d   ALTER TABLE ONLY public.sales_fact_table
    ADD CONSTRAINT sales_fact_table_pkey PRIMARY KEY (id);
 P   ALTER TABLE ONLY public.sales_fact_table DROP CONSTRAINT sales_fact_table_pkey;
       public         postgres    false    245            [           2606    18177    sales_clients salesclients_pkey 
   CONSTRAINT     ]   ALTER TABLE ONLY public.sales_clients
    ADD CONSTRAINT salesclients_pkey PRIMARY KEY (id);
 I   ALTER TABLE ONLY public.sales_clients DROP CONSTRAINT salesclients_pkey;
       public         postgres    false    221            _           2606    18193    sales_date salesdate_pkey 
   CONSTRAINT     W   ALTER TABLE ONLY public.sales_date
    ADD CONSTRAINT salesdate_pkey PRIMARY KEY (id);
 C   ALTER TABLE ONLY public.sales_date DROP CONSTRAINT salesdate_pkey;
       public         postgres    false    224            k           2606    18256    sales_goods salesgoods_pkey 
   CONSTRAINT     Y   ALTER TABLE ONLY public.sales_goods
    ADD CONSTRAINT salesgoods_pkey PRIMARY KEY (id);
 E   ALTER TABLE ONLY public.sales_goods DROP CONSTRAINT salesgoods_pkey;
       public         postgres    false    236            e           2606    18222    sales_storage salesstorage_pkey 
   CONSTRAINT     ]   ALTER TABLE ONLY public.sales_storage
    ADD CONSTRAINT salesstorage_pkey PRIMARY KEY (id);
 I   ALTER TABLE ONLY public.sales_storage DROP CONSTRAINT salesstorage_pkey;
       public         postgres    false    230            W           2606    17954    storages storages_pkey 
   CONSTRAINT     T   ALTER TABLE ONLY public.storages
    ADD CONSTRAINT storages_pkey PRIMARY KEY (id);
 @   ALTER TABLE ONLY public.storages DROP CONSTRAINT storages_pkey;
       public         postgres    false    217            Y           2606    17956    supply supply_pkey 
   CONSTRAINT     P   ALTER TABLE ONLY public.supply
    ADD CONSTRAINT supply_pkey PRIMARY KEY (id);
 <   ALTER TABLE ONLY public.supply DROP CONSTRAINT supply_pkey;
       public         postgres    false    219            �           2620    17957     recgoods remains_recgoods_actual    TRIGGER     �   CREATE TRIGGER remains_recgoods_actual BEFORE UPDATE ON public.recgoods FOR EACH ROW EXECUTE PROCEDURE public.remains_actual();
 9   DROP TRIGGER remains_recgoods_actual ON public.recgoods;
       public       postgres    false    261    213            v           2606    17978    city city_region_fkey    FK CONSTRAINT     t   ALTER TABLE ONLY public.city
    ADD CONSTRAINT city_region_fkey FOREIGN KEY (region) REFERENCES public.region(id);
 ?   ALTER TABLE ONLY public.city DROP CONSTRAINT city_region_fkey;
       public       postgres    false    214    2899    196            w           2606    17983 '   client_groups client_groups_parent_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.client_groups
    ADD CONSTRAINT client_groups_parent_fkey FOREIGN KEY (parent) REFERENCES public.client_groups(id);
 Q   ALTER TABLE ONLY public.client_groups DROP CONSTRAINT client_groups_parent_fkey;
       public       postgres    false    2881    198    198            x           2606    17988    clients clients_city_fkey    FK CONSTRAINT     t   ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_city_fkey FOREIGN KEY (city) REFERENCES public.city(id);
 C   ALTER TABLE ONLY public.clients DROP CONSTRAINT clients_city_fkey;
       public       postgres    false    200    2879    196            y           2606    17993 "   clients clients_client_groups_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_client_groups_fkey FOREIGN KEY (client_groups) REFERENCES public.client_groups(id);
 L   ALTER TABLE ONLY public.clients DROP CONSTRAINT clients_client_groups_fkey;
       public       postgres    false    2881    200    198            z           2606    17998    goods goods_g_group_fkey    FK CONSTRAINT     ~   ALTER TABLE ONLY public.goods
    ADD CONSTRAINT goods_g_group_fkey FOREIGN KEY (g_group) REFERENCES public.goods_groups(id);
 B   ALTER TABLE ONLY public.goods DROP CONSTRAINT goods_g_group_fkey;
       public       postgres    false    202    2887    203            {           2606    18003 %   goods_groups goods_groups_parent_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.goods_groups
    ADD CONSTRAINT goods_groups_parent_fkey FOREIGN KEY (parent) REFERENCES public.goods_groups(id);
 O   ALTER TABLE ONLY public.goods_groups DROP CONSTRAINT goods_groups_parent_fkey;
       public       postgres    false    203    203    2887            |           2606    18008    incgoods incgoods_goods_fkey    FK CONSTRAINT     y   ALTER TABLE ONLY public.incgoods
    ADD CONSTRAINT incgoods_goods_fkey FOREIGN KEY (goods) REFERENCES public.goods(id);
 F   ALTER TABLE ONLY public.incgoods DROP CONSTRAINT incgoods_goods_fkey;
       public       postgres    false    202    2885    206            }           2606    18013    incgoods incgoods_id_fkey    FK CONSTRAINT     t   ALTER TABLE ONLY public.incgoods
    ADD CONSTRAINT incgoods_id_fkey FOREIGN KEY (id) REFERENCES public.income(id);
 C   ALTER TABLE ONLY public.incgoods DROP CONSTRAINT incgoods_id_fkey;
       public       postgres    false    206    207    2891            ~           2606    18018    income income_client_fkey    FK CONSTRAINT     y   ALTER TABLE ONLY public.income
    ADD CONSTRAINT income_client_fkey FOREIGN KEY (client) REFERENCES public.clients(id);
 C   ALTER TABLE ONLY public.income DROP CONSTRAINT income_client_fkey;
       public       postgres    false    207    200    2883                       2606    18023    income income_storage_fkey    FK CONSTRAINT     |   ALTER TABLE ONLY public.income
    ADD CONSTRAINT income_storage_fkey FOREIGN KEY (storage) REFERENCES public.storages(id);
 D   ALTER TABLE ONLY public.income DROP CONSTRAINT income_storage_fkey;
       public       postgres    false    217    2903    207            �           2606    18028    irlink irlink_goods_fkey    FK CONSTRAINT     u   ALTER TABLE ONLY public.irlink
    ADD CONSTRAINT irlink_goods_fkey FOREIGN KEY (goods) REFERENCES public.goods(id);
 B   ALTER TABLE ONLY public.irlink DROP CONSTRAINT irlink_goods_fkey;
       public       postgres    false    209    202    2885            �           2606    18033    irlink irlink_i_id_fkey    FK CONSTRAINT     t   ALTER TABLE ONLY public.irlink
    ADD CONSTRAINT irlink_i_id_fkey FOREIGN KEY (i_id) REFERENCES public.income(id);
 A   ALTER TABLE ONLY public.irlink DROP CONSTRAINT irlink_i_id_fkey;
       public       postgres    false    209    2891    207            �           2606    18038    irlink irlink_r_id_fkey    FK CONSTRAINT     t   ALTER TABLE ONLY public.irlink
    ADD CONSTRAINT irlink_r_id_fkey FOREIGN KEY (r_id) REFERENCES public.recept(id);
 A   ALTER TABLE ONLY public.irlink DROP CONSTRAINT irlink_r_id_fkey;
       public       postgres    false    209    2895    211            �           2606    18289 (   purchase_fact_table purchase_client_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.purchase_fact_table
    ADD CONSTRAINT purchase_client_fkey FOREIGN KEY (client_id) REFERENCES public.purchase_clients(id);
 R   ALTER TABLE ONLY public.purchase_fact_table DROP CONSTRAINT purchase_client_fkey;
       public       postgres    false    241    222    2909            �           2606    18284 &   purchase_fact_table purchase_date_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.purchase_fact_table
    ADD CONSTRAINT purchase_date_fkey FOREIGN KEY (ddate_id) REFERENCES public.purchase_date(id);
 P   ALTER TABLE ONLY public.purchase_fact_table DROP CONSTRAINT purchase_date_fkey;
       public       postgres    false    2915    241    228            �           2606    18299 '   purchase_fact_table purchase_goods_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.purchase_fact_table
    ADD CONSTRAINT purchase_goods_fkey FOREIGN KEY (goods_id) REFERENCES public.purchase_goods(id);
 Q   ALTER TABLE ONLY public.purchase_fact_table DROP CONSTRAINT purchase_goods_fkey;
       public       postgres    false    241    2925    238            �           2606    18294 )   purchase_fact_table purchase_storage_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.purchase_fact_table
    ADD CONSTRAINT purchase_storage_fkey FOREIGN KEY (storage_id) REFERENCES public.purchase_storage(id);
 S   ALTER TABLE ONLY public.purchase_fact_table DROP CONSTRAINT purchase_storage_fkey;
       public       postgres    false    241    232    2919            �           2606    18043    recept recept_client_fkey    FK CONSTRAINT     y   ALTER TABLE ONLY public.recept
    ADD CONSTRAINT recept_client_fkey FOREIGN KEY (client) REFERENCES public.clients(id);
 C   ALTER TABLE ONLY public.recept DROP CONSTRAINT recept_client_fkey;
       public       postgres    false    2883    200    211            �           2606    18048    recept recept_storage_fkey    FK CONSTRAINT     |   ALTER TABLE ONLY public.recept
    ADD CONSTRAINT recept_storage_fkey FOREIGN KEY (storage) REFERENCES public.storages(id);
 D   ALTER TABLE ONLY public.recept DROP CONSTRAINT recept_storage_fkey;
       public       postgres    false    2903    217    211            �           2606    18053    recgoods recgoods_goods_fkey    FK CONSTRAINT     y   ALTER TABLE ONLY public.recgoods
    ADD CONSTRAINT recgoods_goods_fkey FOREIGN KEY (goods) REFERENCES public.goods(id);
 F   ALTER TABLE ONLY public.recgoods DROP CONSTRAINT recgoods_goods_fkey;
       public       postgres    false    213    2885    202            �           2606    18058    recgoods recgoods_id_fkey    FK CONSTRAINT     t   ALTER TABLE ONLY public.recgoods
    ADD CONSTRAINT recgoods_id_fkey FOREIGN KEY (id) REFERENCES public.recept(id);
 C   ALTER TABLE ONLY public.recgoods DROP CONSTRAINT recgoods_id_fkey;
       public       postgres    false    211    2895    213            �           2606    18314 $   remains_fact_table remains_date_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.remains_fact_table
    ADD CONSTRAINT remains_date_fkey FOREIGN KEY (ddate_id) REFERENCES public.remains_date(id);
 N   ALTER TABLE ONLY public.remains_fact_table DROP CONSTRAINT remains_date_fkey;
       public       postgres    false    226    2913    243            �           2606    18063    remains remains_goods_fkey    FK CONSTRAINT     w   ALTER TABLE ONLY public.remains
    ADD CONSTRAINT remains_goods_fkey FOREIGN KEY (goods) REFERENCES public.goods(id);
 D   ALTER TABLE ONLY public.remains DROP CONSTRAINT remains_goods_fkey;
       public       postgres    false    216    202    2885            �           2606    18319 %   remains_fact_table remains_goods_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.remains_fact_table
    ADD CONSTRAINT remains_goods_fkey FOREIGN KEY (goods_id) REFERENCES public.remains_goods(id);
 O   ALTER TABLE ONLY public.remains_fact_table DROP CONSTRAINT remains_goods_fkey;
       public       postgres    false    243    2927    239            �           2606    18068    remains remains_storage_fkey    FK CONSTRAINT     ~   ALTER TABLE ONLY public.remains
    ADD CONSTRAINT remains_storage_fkey FOREIGN KEY (storage) REFERENCES public.storages(id);
 F   ALTER TABLE ONLY public.remains DROP CONSTRAINT remains_storage_fkey;
       public       postgres    false    216    217    2903            �           2606    18324 '   remains_fact_table remains_storage_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.remains_fact_table
    ADD CONSTRAINT remains_storage_fkey FOREIGN KEY (storage_id) REFERENCES public.remains_storage(id);
 Q   ALTER TABLE ONLY public.remains_fact_table DROP CONSTRAINT remains_storage_fkey;
       public       postgres    false    2921    243    234            �           2606    18337 "   sales_fact_table sales_client_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.sales_fact_table
    ADD CONSTRAINT sales_client_fkey FOREIGN KEY (client_id) REFERENCES public.sales_clients(id);
 L   ALTER TABLE ONLY public.sales_fact_table DROP CONSTRAINT sales_client_fkey;
       public       postgres    false    221    2907    245            �           2606    18342     sales_fact_table sales_date_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.sales_fact_table
    ADD CONSTRAINT sales_date_fkey FOREIGN KEY (ddate_id) REFERENCES public.sales_date(id);
 J   ALTER TABLE ONLY public.sales_fact_table DROP CONSTRAINT sales_date_fkey;
       public       postgres    false    2911    224    245            �           2606    18347 !   sales_fact_table sales_goods_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.sales_fact_table
    ADD CONSTRAINT sales_goods_fkey FOREIGN KEY (goods_id) REFERENCES public.sales_goods(id);
 K   ALTER TABLE ONLY public.sales_fact_table DROP CONSTRAINT sales_goods_fkey;
       public       postgres    false    236    245    2923            �           2606    18352 #   sales_fact_table sales_storage_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.sales_fact_table
    ADD CONSTRAINT sales_storage_fkey FOREIGN KEY (storage_id) REFERENCES public.sales_storage(id);
 M   ALTER TABLE ONLY public.sales_fact_table DROP CONSTRAINT sales_storage_fkey;
       public       postgres    false    230    245    2917            �           2606    18073    supply supply_storage_fkey    FK CONSTRAINT     |   ALTER TABLE ONLY public.supply
    ADD CONSTRAINT supply_storage_fkey FOREIGN KEY (storage) REFERENCES public.storages(id);
 D   ALTER TABLE ONLY public.supply DROP CONSTRAINT supply_storage_fkey;
       public       postgres    false    2903    219    217               T  x�]�ˍA�s�8 ��d}|��e� �"7��_�Vbl�������TU�����{��O�qM�J�_q�?�_�Ǐx�/�����3�?�b5��pM�Z��8�.n��/�����G�>^�)^xfr�)~2���!u)�����.�0υ�-�\�(��\i �|�8#�s����2Xi����~�,hr��mJ�9� �͊��ޭ�Ŋȑ��Б�VĎ|�<�J�ȯVD�|����B��_���nU��oVE�|�=�U�����8K���F�W�����P��+{�D_��&z�gk�G>V��R�D_��&z�#Q�ȇK�o�o�׉o��G����qr\��o�}��E�콋�p���\�N}�S���e�蝯l=�Q���w�;��.�N}}��w�#ǋ�ņ�;�~�������~�����G>J�G~�!��;g�~��C������~�~𭝢�O�.of�#%�#����~��X%�ɹ��G~�%�I���~�~R�D?99Ko{���䝳D��_�_�/�/N�����M� �㱉ߪM |Q6y�u|�6y�5��d���>Z~�`fO2�=         �   x�}�1�@E�SpA/�	8�`�vvjbgC����
n��������?1��	&)��b�	�
#z�^YnR��[9��B��)��	a(�Ⴓ��r6�E���g{J8�ٿ�(�TG+upl�;"���=FmYS��yD��a�40DZ�jU���W(�b��-u��         �   x�e��n�@D뻯X�6V���/��HRJ����
#H�J�Ԗ�8���?b�
(�6w;;o&5��#�:�'�^�p�� :G�
G�Ƒ�w"���%�X������#�e������5.����IK]4��~Lj�6�ux����,pN��≉%5T.)���x �e�Wf���uz��ad�i��xG��b���~��.�tQ(��Xk/2�n         �   x�]�MJA��]�h��Гq����ppB���g�E]�;���11�^�(�ɦ��^��uE.r�`��:�Q�q#5Ӧ(4�1˺K\,�5�Q�����?�ȥ�9|�Ԍ�RG|)�$Hb�mͱ��t�jw��t�C�`�1/�"XW�
����x����/]ar,�,R?q�5�Z�v�!}�z|1�?r�c�x�[gg���m����� ���WE�]��[         �   x�]�=�P���Sx@���à��3y��AHHg����(,,��v�2C����0b`�`��sC'��'k����f�"�N��Q����~�q����	�Fe��`�_/�*�Oƽj�[[��Ӗ^���)c�         H   x�M���0���0����j��2#�R� ��'��˂�B�)�f��o�����5\񷩶=���j�         ?   x�Eȱ !�������^�7\��u(���/���궽N$�˻l��Lx��D� �7�         !   x�3�4�4bs ij�e���\�=... N�Y      )   �   x�e�;nAD�S�&^#�N � 1�Cˁ#g|$"��EɁ���� ��oD�� U2��~U]����y���ڏ�O�6j$(G��a>�%������l�P-��0X"�r���=N6�w�sJ��!�@k�������>�R�j�$��y;Q{n!:��h��CbI�[��q�!��o�~N`�{��$p���Xj�r��z[�b�� I��      /   ,   x�3�4202�50�50�2Cp���S. ���1����� 	m      <   s   x�m�]
�0����H�z��9QA�hHh�*Ж�hf�����BB�L7��/u�FV�X�zs^��c�!��_�P���)��W�P� d�A(��6��(�q���T-L�c#��K$�      9   m   x�-���@D��b��Y��bpD@J���[:Y�0�{�h��y-����ǌ�FcF�*�f���H0�Mzpca�'����АL���sx�/�"թ�ZU�9&e,�      3   ;   x�3�0�b���;.��xaׅ�.컰�¾���B�/l����NC�=... y��         6   x�E�� �w�s�3�E�u�e�۠P�p�g�C0�{BN����2�]I�lL          R   x�U���@��2��p=t��C�\L_�Bݑ�Fd�z����/�Ĭmzm�
�9���"�f���V�q�}��1�X      !   �   x�u���0D��*� H��q�#HHHܐ���$Įa�#ƾp�a�z�3�;�6��ek��GĤn�zu�N[��<!���Rq��eۨӳ���,�=>K����/��X�cE�@�|�0#�)/Ymi�`��
�h��~��      #       x�3�4�4aCK]c]3N3�=... 8��      -      x�3�420��50�50����� g�      >      x�3�000�4"C(�i�i����� @�	      :   %   x�3⼰����9�МӔӘ����+F��� �	`      5   ;   x�3�0�b���;.��xaׅ�.컰�¾���B�/l����NC�=... y��      (   �   x�e�;nAD�S�&^#�N � 1�Cˁ#g|$"��EɁ���� ��oD�� U2��~U]����y���ڏ�O�6j$(G��a>�%������l�P-��0X"�r���=N6�w�sJ��!�@k�������>�R�j�$��y;Q{n!:��h��CbI�[��q�!��o�~N`�{��$p���Xj�r��z[�b�� I��      +   #   x�3�4202�50�5��2Cp,��s�=... �	?      @   n   x����!E��s1���{I�u�L)�#�.��P��@{���l�pG�{)��(�������k�FI`�ső}�g�^*�R�N�ش�Eu�;x\�z��x���)}����I&�      7   �   x�u�=
1���)k��kX=���\Q�D�wm,,�;m�?X����FN���L�$�y_^|�'<��).Hɷ�e�PE�"a���9!$C��F�2�8����Y�PhT��BƱp3�RQ�25��V�0��<��DN����X�X����f/��8<�r�ƨ����Ѱ�a-�i�3�=�%�N��\4_����?�jw0赣�8�����R/	�x      1   d   x����0߾*\��N�	H<PH4���aa9ش0�Q����X(l(�HE#/�hv�O�ؕ��j8�9��nd�;�G��zr�}�o��~�� ";�=+      $   |   x�M���@�*����"@r@������~Z�k�J�7	���f���<����;W�DT�?7��9��,��x���ț�Ѷtʋ����*�����L�&�I��'�����m�KY"�yKY�      &      x������ � �     