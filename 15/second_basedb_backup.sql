PGDMP     5    2                x         
   StoragesDB    11.7    11.7 �    �           0    0    ENCODING    ENCODING        SET client_encoding = 'UTF8';
                       false            �           0    0 
   STDSTRINGS 
   STDSTRINGS     (   SET standard_conforming_strings = 'on';
                       false            �           0    0 
   SEARCHPATH 
   SEARCHPATH     8   SELECT pg_catalog.set_config('search_path', '', false);
                       false            �           1262    16707 
   StoragesDB    DATABASE     �   CREATE DATABASE "StoragesDB" WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'Russian_Russia.1251' LC_CTYPE = 'Russian_Russia.1251';
    DROP DATABASE "StoragesDB";
             postgres    false            �            1255    17401    gen_t(integer)    FUNCTION     +  CREATE FUNCTION public.gen_t(n integer) RETURNS TABLE(id integer)
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
       public       postgres    false            �            1255    17070    my_f(date, date)    FUNCTION     �  CREATE FUNCTION public.my_f(d1 date, d2 date) RETURNS TABLE(goods integer, volume numeric)
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
       public       postgres    false            �            1255    17084    my_f5(integer)    FUNCTION     P  CREATE FUNCTION public.my_f5(ii integer) RETURNS integer
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
       public       postgres    false            �            1255    17288    remains_actual()    FUNCTION     �  CREATE FUNCTION public.remains_actual() RETURNS trigger
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
       public       postgres    false            �            1255    17137    sales_trend(date, date)    FUNCTION     �  CREATE FUNCTION public.sales_trend(d_start date, d_end date) RETURNS TABLE(g_group integer, ddate date, predict double precision, eerror double precision)
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
       public       postgres    false            �            1255    17061    test_sp(date, date) 	   PROCEDURE     �  CREATE PROCEDURE public.test_sp(d1 date, d2 date)
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
       public       postgres    false            �            1259    16970    bank_income    TABLE     s   CREATE TABLE public.bank_income (
    id integer NOT NULL,
    ddate date,
    summ integer,
    client integer
);
    DROP TABLE public.bank_income;
       public         postgres    false            �            1259    16968    bank_income_id_seq    SEQUENCE     �   CREATE SEQUENCE public.bank_income_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 )   DROP SEQUENCE public.bank_income_id_seq;
       public       postgres    false    223            �           0    0    bank_income_id_seq    SEQUENCE OWNED BY     I   ALTER SEQUENCE public.bank_income_id_seq OWNED BY public.bank_income.id;
            public       postgres    false    222            �            1259    16928    bank_recept    TABLE     s   CREATE TABLE public.bank_recept (
    id integer NOT NULL,
    ddate date,
    summ integer,
    client integer
);
    DROP TABLE public.bank_recept;
       public         postgres    false            �            1259    16926    bank_recept_id_seq    SEQUENCE     �   CREATE SEQUENCE public.bank_recept_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 )   DROP SEQUENCE public.bank_recept_id_seq;
       public       postgres    false    217            �           0    0    bank_recept_id_seq    SEQUENCE OWNED BY     I   ALTER SEQUENCE public.bank_recept_id_seq OWNED BY public.bank_recept.id;
            public       postgres    false    216            �            1259    16956    cassa_income    TABLE     t   CREATE TABLE public.cassa_income (
    id integer NOT NULL,
    ddate date,
    summ integer,
    client integer
);
     DROP TABLE public.cassa_income;
       public         postgres    false            �            1259    16954    cassa_income_id_seq    SEQUENCE     �   CREATE SEQUENCE public.cassa_income_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 *   DROP SEQUENCE public.cassa_income_id_seq;
       public       postgres    false    221            �           0    0    cassa_income_id_seq    SEQUENCE OWNED BY     K   ALTER SEQUENCE public.cassa_income_id_seq OWNED BY public.cassa_income.id;
            public       postgres    false    220            �            1259    16943    cassa_recept    TABLE     t   CREATE TABLE public.cassa_recept (
    id integer NOT NULL,
    ddate date,
    summ integer,
    client integer
);
     DROP TABLE public.cassa_recept;
       public         postgres    false            �            1259    16941    cassa_recept_id_seq    SEQUENCE     �   CREATE SEQUENCE public.cassa_recept_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 *   DROP SEQUENCE public.cassa_recept_id_seq;
       public       postgres    false    219            �           0    0    cassa_recept_id_seq    SEQUENCE OWNED BY     K   ALTER SEQUENCE public.cassa_recept_id_seq OWNED BY public.cassa_recept.id;
            public       postgres    false    218            �            1259    16783    city    TABLE     Y   CREATE TABLE public.city (
    id integer NOT NULL,
    name text,
    region integer
);
    DROP TABLE public.city;
       public         postgres    false            �            1259    16781    city_id_seq    SEQUENCE     �   CREATE SEQUENCE public.city_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 "   DROP SEQUENCE public.city_id_seq;
       public       postgres    false    203            �           0    0    city_id_seq    SEQUENCE OWNED BY     ;   ALTER SEQUENCE public.city_id_seq OWNED BY public.city.id;
            public       postgres    false    202            �            1259    17441    client_groups    TABLE     b   CREATE TABLE public.client_groups (
    id integer NOT NULL,
    name text,
    parent integer
);
 !   DROP TABLE public.client_groups;
       public         postgres    false            �            1259    17439    client_groups_id_seq    SEQUENCE     �   CREATE SEQUENCE public.client_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 +   DROP SEQUENCE public.client_groups_id_seq;
       public       postgres    false    233            �           0    0    client_groups_id_seq    SEQUENCE OWNED BY     M   ALTER SEQUENCE public.client_groups_id_seq OWNED BY public.client_groups.id;
            public       postgres    false    232            �            1259    16799    clients    TABLE     �   CREATE TABLE public.clients (
    id integer NOT NULL,
    name text,
    address text,
    city integer,
    client_groups integer
);
    DROP TABLE public.clients;
       public         postgres    false            �            1259    16797    clients_id_seq    SEQUENCE     �   CREATE SEQUENCE public.clients_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 %   DROP SEQUENCE public.clients_id_seq;
       public       postgres    false    205            �           0    0    clients_id_seq    SEQUENCE OWNED BY     A   ALTER SEQUENCE public.clients_id_seq OWNED BY public.clients.id;
            public       postgres    false    204            �            1259    16884    goods    TABLE     �   CREATE TABLE public.goods (
    id integer NOT NULL,
    g_group integer,
    name text,
    weight real,
    length real,
    height real,
    width real
);
    DROP TABLE public.goods;
       public         postgres    false            �            1259    16864    goods_groups    TABLE     a   CREATE TABLE public.goods_groups (
    id integer NOT NULL,
    name text,
    parent integer
);
     DROP TABLE public.goods_groups;
       public         postgres    false            �            1259    16862    goods_groups_id_seq    SEQUENCE     �   CREATE SEQUENCE public.goods_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 *   DROP SEQUENCE public.goods_groups_id_seq;
       public       postgres    false    213            �           0    0    goods_groups_id_seq    SEQUENCE OWNED BY     K   ALTER SEQUENCE public.goods_groups_id_seq OWNED BY public.goods_groups.id;
            public       postgres    false    212            �            1259    16882    goods_id_seq    SEQUENCE     �   CREATE SEQUENCE public.goods_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 #   DROP SEQUENCE public.goods_id_seq;
       public       postgres    false    215            �           0    0    goods_id_seq    SEQUENCE OWNED BY     =   ALTER SEQUENCE public.goods_id_seq OWNED BY public.goods.id;
            public       postgres    false    214            �            1259    16994    incgoods    TABLE     �   CREATE TABLE public.incgoods (
    id integer NOT NULL,
    subid integer NOT NULL,
    goods integer,
    volume integer,
    price integer
);
    DROP TABLE public.incgoods;
       public         postgres    false            �            1259    16844    income    TABLE     �   CREATE TABLE public.income (
    id integer NOT NULL,
    ddate date,
    ndoc integer,
    client integer,
    storage integer
);
    DROP TABLE public.income;
       public         postgres    false            �            1259    16842    income_id_seq    SEQUENCE     �   CREATE SEQUENCE public.income_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE public.income_id_seq;
       public       postgres    false    211            �           0    0    income_id_seq    SEQUENCE OWNED BY     ?   ALTER SEQUENCE public.income_id_seq OWNED BY public.income.id;
            public       postgres    false    210            �            1259    17367    irlink    TABLE     �   CREATE TABLE public.irlink (
    id integer NOT NULL,
    i_id integer,
    i_subid integer,
    r_id integer,
    r_subid integer,
    goods integer,
    volume integer
);
    DROP TABLE public.irlink;
       public         postgres    false            �            1259    17365    irlink_id_seq    SEQUENCE     �   CREATE SEQUENCE public.irlink_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE public.irlink_id_seq;
       public       postgres    false    231            �           0    0    irlink_id_seq    SEQUENCE OWNED BY     ?   ALTER SEQUENCE public.irlink_id_seq OWNED BY public.irlink.id;
            public       postgres    false    230            �            1259    16826    recept    TABLE     �   CREATE TABLE public.recept (
    id integer NOT NULL,
    ddate date,
    ndoc integer,
    client integer,
    storage integer
);
    DROP TABLE public.recept;
       public         postgres    false            �            1259    16824    recept_id_seq    SEQUENCE     �   CREATE SEQUENCE public.recept_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE public.recept_id_seq;
       public       postgres    false    209            �           0    0    recept_id_seq    SEQUENCE OWNED BY     ?   ALTER SEQUENCE public.recept_id_seq OWNED BY public.recept.id;
            public       postgres    false    208            �            1259    17007    recgoods    TABLE     �   CREATE TABLE public.recgoods (
    id integer NOT NULL,
    subid integer NOT NULL,
    goods integer,
    volume integer,
    price real
);
    DROP TABLE public.recgoods;
       public         postgres    false            �            1259    16772    region    TABLE     G   CREATE TABLE public.region (
    id integer NOT NULL,
    name text
);
    DROP TABLE public.region;
       public         postgres    false            �            1259    16770    region_id_seq    SEQUENCE     �   CREATE SEQUENCE public.region_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE public.region_id_seq;
       public       postgres    false    201            �           0    0    region_id_seq    SEQUENCE OWNED BY     ?   ALTER SEQUENCE public.region_id_seq OWNED BY public.region.id;
            public       postgres    false    200            �            1259    17246    remains    TABLE     �   CREATE TABLE public.remains (
    id integer NOT NULL,
    subid integer NOT NULL,
    goods integer,
    storage integer,
    ddate date,
    volume integer
);
    DROP TABLE public.remains;
       public         postgres    false            �            1259    16815    storages    TABLE     ]   CREATE TABLE public.storages (
    id integer NOT NULL,
    name text,
    active integer
);
    DROP TABLE public.storages;
       public         postgres    false            �            1259    16813    storages_id_seq    SEQUENCE     �   CREATE SEQUENCE public.storages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 &   DROP SEQUENCE public.storages_id_seq;
       public       postgres    false    207            �           0    0    storages_id_seq    SEQUENCE OWNED BY     C   ALTER SEQUENCE public.storages_id_seq OWNED BY public.storages.id;
            public       postgres    false    206            �            1259    16983    supply    TABLE     �   CREATE TABLE public.supply (
    id integer NOT NULL,
    storage integer,
    ddate date,
    summ integer,
    volume integer,
    cnt integer
);
    DROP TABLE public.supply;
       public         postgres    false            �            1259    16981    supply_id_seq    SEQUENCE     �   CREATE SEQUENCE public.supply_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE public.supply_id_seq;
       public       postgres    false    225            �           0    0    supply_id_seq    SEQUENCE OWNED BY     ?   ALTER SEQUENCE public.supply_id_seq OWNED BY public.supply.id;
            public       postgres    false    224            �            1259    17295    test    TABLE     A   CREATE TABLE public.test (
    val1 integer,
    val2 integer
);
    DROP TABLE public.test;
       public         postgres    false            �
           2604    16973    bank_income id    DEFAULT     p   ALTER TABLE ONLY public.bank_income ALTER COLUMN id SET DEFAULT nextval('public.bank_income_id_seq'::regclass);
 =   ALTER TABLE public.bank_income ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    223    222    223            �
           2604    16931    bank_recept id    DEFAULT     p   ALTER TABLE ONLY public.bank_recept ALTER COLUMN id SET DEFAULT nextval('public.bank_recept_id_seq'::regclass);
 =   ALTER TABLE public.bank_recept ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    216    217    217            �
           2604    16959    cassa_income id    DEFAULT     r   ALTER TABLE ONLY public.cassa_income ALTER COLUMN id SET DEFAULT nextval('public.cassa_income_id_seq'::regclass);
 >   ALTER TABLE public.cassa_income ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    220    221    221            �
           2604    16946    cassa_recept id    DEFAULT     r   ALTER TABLE ONLY public.cassa_recept ALTER COLUMN id SET DEFAULT nextval('public.cassa_recept_id_seq'::regclass);
 >   ALTER TABLE public.cassa_recept ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    218    219    219            �
           2604    16786    city id    DEFAULT     b   ALTER TABLE ONLY public.city ALTER COLUMN id SET DEFAULT nextval('public.city_id_seq'::regclass);
 6   ALTER TABLE public.city ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    203    202    203                        2604    17444    client_groups id    DEFAULT     t   ALTER TABLE ONLY public.client_groups ALTER COLUMN id SET DEFAULT nextval('public.client_groups_id_seq'::regclass);
 ?   ALTER TABLE public.client_groups ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    233    232    233            �
           2604    16802 
   clients id    DEFAULT     h   ALTER TABLE ONLY public.clients ALTER COLUMN id SET DEFAULT nextval('public.clients_id_seq'::regclass);
 9   ALTER TABLE public.clients ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    204    205    205            �
           2604    16887    goods id    DEFAULT     d   ALTER TABLE ONLY public.goods ALTER COLUMN id SET DEFAULT nextval('public.goods_id_seq'::regclass);
 7   ALTER TABLE public.goods ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    214    215    215            �
           2604    16867    goods_groups id    DEFAULT     r   ALTER TABLE ONLY public.goods_groups ALTER COLUMN id SET DEFAULT nextval('public.goods_groups_id_seq'::regclass);
 >   ALTER TABLE public.goods_groups ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    212    213    213            �
           2604    16847 	   income id    DEFAULT     f   ALTER TABLE ONLY public.income ALTER COLUMN id SET DEFAULT nextval('public.income_id_seq'::regclass);
 8   ALTER TABLE public.income ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    211    210    211            �
           2604    17370 	   irlink id    DEFAULT     f   ALTER TABLE ONLY public.irlink ALTER COLUMN id SET DEFAULT nextval('public.irlink_id_seq'::regclass);
 8   ALTER TABLE public.irlink ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    230    231    231            �
           2604    16829 	   recept id    DEFAULT     f   ALTER TABLE ONLY public.recept ALTER COLUMN id SET DEFAULT nextval('public.recept_id_seq'::regclass);
 8   ALTER TABLE public.recept ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    209    208    209            �
           2604    16775 	   region id    DEFAULT     f   ALTER TABLE ONLY public.region ALTER COLUMN id SET DEFAULT nextval('public.region_id_seq'::regclass);
 8   ALTER TABLE public.region ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    201    200    201            �
           2604    16818    storages id    DEFAULT     j   ALTER TABLE ONLY public.storages ALTER COLUMN id SET DEFAULT nextval('public.storages_id_seq'::regclass);
 :   ALTER TABLE public.storages ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    207    206    207            �
           2604    16986 	   supply id    DEFAULT     f   ALTER TABLE ONLY public.supply ALTER COLUMN id SET DEFAULT nextval('public.supply_id_seq'::regclass);
 8   ALTER TABLE public.supply ALTER COLUMN id DROP DEFAULT;
       public       postgres    false    224    225    225            �          0    16970    bank_income 
   TABLE DATA               >   COPY public.bank_income (id, ddate, summ, client) FROM stdin;
    public       postgres    false    223   .�       �          0    16928    bank_recept 
   TABLE DATA               >   COPY public.bank_recept (id, ddate, summ, client) FROM stdin;
    public       postgres    false    217   K�       �          0    16956    cassa_income 
   TABLE DATA               ?   COPY public.cassa_income (id, ddate, summ, client) FROM stdin;
    public       postgres    false    221   h�       �          0    16943    cassa_recept 
   TABLE DATA               ?   COPY public.cassa_recept (id, ddate, summ, client) FROM stdin;
    public       postgres    false    219   ��       �          0    16783    city 
   TABLE DATA               0   COPY public.city (id, name, region) FROM stdin;
    public       postgres    false    203   ��       �          0    17441    client_groups 
   TABLE DATA               9   COPY public.client_groups (id, name, parent) FROM stdin;
    public       postgres    false    233   �       �          0    16799    clients 
   TABLE DATA               I   COPY public.clients (id, name, address, city, client_groups) FROM stdin;
    public       postgres    false    205   ��       �          0    16884    goods 
   TABLE DATA               Q   COPY public.goods (id, g_group, name, weight, length, height, width) FROM stdin;
    public       postgres    false    215   ��       �          0    16864    goods_groups 
   TABLE DATA               8   COPY public.goods_groups (id, name, parent) FROM stdin;
    public       postgres    false    213   ��       �          0    16994    incgoods 
   TABLE DATA               C   COPY public.incgoods (id, subid, goods, volume, price) FROM stdin;
    public       postgres    false    226   4�       �          0    16844    income 
   TABLE DATA               B   COPY public.income (id, ddate, ndoc, client, storage) FROM stdin;
    public       postgres    false    211   ��       �          0    17367    irlink 
   TABLE DATA               Q   COPY public.irlink (id, i_id, i_subid, r_id, r_subid, goods, volume) FROM stdin;
    public       postgres    false    231   ۿ       �          0    16826    recept 
   TABLE DATA               B   COPY public.recept (id, ddate, ndoc, client, storage) FROM stdin;
    public       postgres    false    209   �       �          0    17007    recgoods 
   TABLE DATA               C   COPY public.recgoods (id, subid, goods, volume, price) FROM stdin;
    public       postgres    false    227   R�       �          0    16772    region 
   TABLE DATA               *   COPY public.region (id, name) FROM stdin;
    public       postgres    false    201   ��       �          0    17246    remains 
   TABLE DATA               K   COPY public.remains (id, subid, goods, storage, ddate, volume) FROM stdin;
    public       postgres    false    228   T�       �          0    16815    storages 
   TABLE DATA               4   COPY public.storages (id, name, active) FROM stdin;
    public       postgres    false    207   ��       �          0    16983    supply 
   TABLE DATA               G   COPY public.supply (id, storage, ddate, summ, volume, cnt) FROM stdin;
    public       postgres    false    225   �       �          0    17295    test 
   TABLE DATA               *   COPY public.test (val1, val2) FROM stdin;
    public       postgres    false    229   -�       �           0    0    bank_income_id_seq    SEQUENCE SET     A   SELECT pg_catalog.setval('public.bank_income_id_seq', 1, false);
            public       postgres    false    222            �           0    0    bank_recept_id_seq    SEQUENCE SET     A   SELECT pg_catalog.setval('public.bank_recept_id_seq', 1, false);
            public       postgres    false    216            �           0    0    cassa_income_id_seq    SEQUENCE SET     B   SELECT pg_catalog.setval('public.cassa_income_id_seq', 1, false);
            public       postgres    false    220            �           0    0    cassa_recept_id_seq    SEQUENCE SET     B   SELECT pg_catalog.setval('public.cassa_recept_id_seq', 1, false);
            public       postgres    false    218            �           0    0    city_id_seq    SEQUENCE SET     ;   SELECT pg_catalog.setval('public.city_id_seq', 106, true);
            public       postgres    false    202            �           0    0    client_groups_id_seq    SEQUENCE SET     C   SELECT pg_catalog.setval('public.client_groups_id_seq', 1, false);
            public       postgres    false    232            �           0    0    clients_id_seq    SEQUENCE SET     =   SELECT pg_catalog.setval('public.clients_id_seq', 1, false);
            public       postgres    false    204            �           0    0    goods_groups_id_seq    SEQUENCE SET     B   SELECT pg_catalog.setval('public.goods_groups_id_seq', 1, false);
            public       postgres    false    212            �           0    0    goods_id_seq    SEQUENCE SET     ;   SELECT pg_catalog.setval('public.goods_id_seq', 1, false);
            public       postgres    false    214            �           0    0    income_id_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('public.income_id_seq', 1, false);
            public       postgres    false    210            �           0    0    irlink_id_seq    SEQUENCE SET     ;   SELECT pg_catalog.setval('public.irlink_id_seq', 6, true);
            public       postgres    false    230            �           0    0    recept_id_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('public.recept_id_seq', 1, false);
            public       postgres    false    208            �           0    0    region_id_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('public.region_id_seq', 1, false);
            public       postgres    false    200            �           0    0    storages_id_seq    SEQUENCE SET     =   SELECT pg_catalog.setval('public.storages_id_seq', 3, true);
            public       postgres    false    206            �           0    0    supply_id_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('public.supply_id_seq', 10, true);
            public       postgres    false    224                       2606    16975    bank_income bank_income_pkey 
   CONSTRAINT     Z   ALTER TABLE ONLY public.bank_income
    ADD CONSTRAINT bank_income_pkey PRIMARY KEY (id);
 F   ALTER TABLE ONLY public.bank_income DROP CONSTRAINT bank_income_pkey;
       public         postgres    false    223                       2606    16933    bank_recept bank_recept_pkey 
   CONSTRAINT     Z   ALTER TABLE ONLY public.bank_recept
    ADD CONSTRAINT bank_recept_pkey PRIMARY KEY (id);
 F   ALTER TABLE ONLY public.bank_recept DROP CONSTRAINT bank_recept_pkey;
       public         postgres    false    217                       2606    16961    cassa_income cassa_income_pkey 
   CONSTRAINT     \   ALTER TABLE ONLY public.cassa_income
    ADD CONSTRAINT cassa_income_pkey PRIMARY KEY (id);
 H   ALTER TABLE ONLY public.cassa_income DROP CONSTRAINT cassa_income_pkey;
       public         postgres    false    221                       2606    16948    cassa_recept cassa_recept_pkey 
   CONSTRAINT     \   ALTER TABLE ONLY public.cassa_recept
    ADD CONSTRAINT cassa_recept_pkey PRIMARY KEY (id);
 H   ALTER TABLE ONLY public.cassa_recept DROP CONSTRAINT cassa_recept_pkey;
       public         postgres    false    219                       2606    16791    city city_pkey 
   CONSTRAINT     L   ALTER TABLE ONLY public.city
    ADD CONSTRAINT city_pkey PRIMARY KEY (id);
 8   ALTER TABLE ONLY public.city DROP CONSTRAINT city_pkey;
       public         postgres    false    203            $           2606    17449     client_groups client_groups_pkey 
   CONSTRAINT     ^   ALTER TABLE ONLY public.client_groups
    ADD CONSTRAINT client_groups_pkey PRIMARY KEY (id);
 J   ALTER TABLE ONLY public.client_groups DROP CONSTRAINT client_groups_pkey;
       public         postgres    false    233                       2606    16807    clients clients_pkey 
   CONSTRAINT     R   ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);
 >   ALTER TABLE ONLY public.clients DROP CONSTRAINT clients_pkey;
       public         postgres    false    205                       2606    16872    goods_groups goods_groups_pkey 
   CONSTRAINT     \   ALTER TABLE ONLY public.goods_groups
    ADD CONSTRAINT goods_groups_pkey PRIMARY KEY (id);
 H   ALTER TABLE ONLY public.goods_groups DROP CONSTRAINT goods_groups_pkey;
       public         postgres    false    213                       2606    16892    goods goods_pkey 
   CONSTRAINT     N   ALTER TABLE ONLY public.goods
    ADD CONSTRAINT goods_pkey PRIMARY KEY (id);
 :   ALTER TABLE ONLY public.goods DROP CONSTRAINT goods_pkey;
       public         postgres    false    215                       2606    17054    incgoods incgoods_pkey 
   CONSTRAINT     [   ALTER TABLE ONLY public.incgoods
    ADD CONSTRAINT incgoods_pkey PRIMARY KEY (id, subid);
 @   ALTER TABLE ONLY public.incgoods DROP CONSTRAINT incgoods_pkey;
       public         postgres    false    226    226                       2606    16849    income income_pkey 
   CONSTRAINT     P   ALTER TABLE ONLY public.income
    ADD CONSTRAINT income_pkey PRIMARY KEY (id);
 <   ALTER TABLE ONLY public.income DROP CONSTRAINT income_pkey;
       public         postgres    false    211            "           2606    17372    irlink irlink_pkey 
   CONSTRAINT     P   ALTER TABLE ONLY public.irlink
    ADD CONSTRAINT irlink_pkey PRIMARY KEY (id);
 <   ALTER TABLE ONLY public.irlink DROP CONSTRAINT irlink_pkey;
       public         postgres    false    231            
           2606    16831    recept recept_pkey 
   CONSTRAINT     P   ALTER TABLE ONLY public.recept
    ADD CONSTRAINT recept_pkey PRIMARY KEY (id);
 <   ALTER TABLE ONLY public.recept DROP CONSTRAINT recept_pkey;
       public         postgres    false    209                       2606    17052    recgoods recgoods_pkey 
   CONSTRAINT     [   ALTER TABLE ONLY public.recgoods
    ADD CONSTRAINT recgoods_pkey PRIMARY KEY (id, subid);
 @   ALTER TABLE ONLY public.recgoods DROP CONSTRAINT recgoods_pkey;
       public         postgres    false    227    227                       2606    16780    region region_pkey 
   CONSTRAINT     P   ALTER TABLE ONLY public.region
    ADD CONSTRAINT region_pkey PRIMARY KEY (id);
 <   ALTER TABLE ONLY public.region DROP CONSTRAINT region_pkey;
       public         postgres    false    201                        2606    17250    remains remains_pkey 
   CONSTRAINT     Y   ALTER TABLE ONLY public.remains
    ADD CONSTRAINT remains_pkey PRIMARY KEY (id, subid);
 >   ALTER TABLE ONLY public.remains DROP CONSTRAINT remains_pkey;
       public         postgres    false    228    228                       2606    16823    storages storages_pkey 
   CONSTRAINT     T   ALTER TABLE ONLY public.storages
    ADD CONSTRAINT storages_pkey PRIMARY KEY (id);
 @   ALTER TABLE ONLY public.storages DROP CONSTRAINT storages_pkey;
       public         postgres    false    207                       2606    16988    supply supply_pkey 
   CONSTRAINT     P   ALTER TABLE ONLY public.supply
    ADD CONSTRAINT supply_pkey PRIMARY KEY (id);
 <   ALTER TABLE ONLY public.supply DROP CONSTRAINT supply_pkey;
       public         postgres    false    225            =           2620    17396     recgoods remains_recgoods_actual    TRIGGER     �   CREATE TRIGGER remains_recgoods_actual BEFORE UPDATE ON public.recgoods FOR EACH ROW EXECUTE PROCEDURE public.remains_actual();
 9   DROP TRIGGER remains_recgoods_actual ON public.recgoods;
       public       postgres    false    251    227            1           2606    16976 #   bank_income bank_income_client_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.bank_income
    ADD CONSTRAINT bank_income_client_fkey FOREIGN KEY (client) REFERENCES public.clients(id);
 M   ALTER TABLE ONLY public.bank_income DROP CONSTRAINT bank_income_client_fkey;
       public       postgres    false    205    2822    223            .           2606    16934 #   bank_recept bank_recept_client_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.bank_recept
    ADD CONSTRAINT bank_recept_client_fkey FOREIGN KEY (client) REFERENCES public.clients(id);
 M   ALTER TABLE ONLY public.bank_recept DROP CONSTRAINT bank_recept_client_fkey;
       public       postgres    false    2822    205    217            0           2606    16962 %   cassa_income cassa_income_client_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.cassa_income
    ADD CONSTRAINT cassa_income_client_fkey FOREIGN KEY (client) REFERENCES public.clients(id);
 O   ALTER TABLE ONLY public.cassa_income DROP CONSTRAINT cassa_income_client_fkey;
       public       postgres    false    205    2822    221            /           2606    16949 %   cassa_recept cassa_recept_client_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.cassa_recept
    ADD CONSTRAINT cassa_recept_client_fkey FOREIGN KEY (client) REFERENCES public.clients(id);
 O   ALTER TABLE ONLY public.cassa_recept DROP CONSTRAINT cassa_recept_client_fkey;
       public       postgres    false    219    205    2822            %           2606    16792    city city_region_fkey    FK CONSTRAINT     t   ALTER TABLE ONLY public.city
    ADD CONSTRAINT city_region_fkey FOREIGN KEY (region) REFERENCES public.region(id);
 ?   ALTER TABLE ONLY public.city DROP CONSTRAINT city_region_fkey;
       public       postgres    false    203    2818    201            <           2606    17450 '   client_groups client_groups_parent_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.client_groups
    ADD CONSTRAINT client_groups_parent_fkey FOREIGN KEY (parent) REFERENCES public.client_groups(id);
 Q   ALTER TABLE ONLY public.client_groups DROP CONSTRAINT client_groups_parent_fkey;
       public       postgres    false    2852    233    233            &           2606    16808    clients clients_city_fkey    FK CONSTRAINT     t   ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_city_fkey FOREIGN KEY (city) REFERENCES public.city(id);
 C   ALTER TABLE ONLY public.clients DROP CONSTRAINT clients_city_fkey;
       public       postgres    false    2820    203    205            '           2606    17455 "   clients clients_client_groups_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_client_groups_fkey FOREIGN KEY (client_groups) REFERENCES public.client_groups(id);
 L   ALTER TABLE ONLY public.clients DROP CONSTRAINT clients_client_groups_fkey;
       public       postgres    false    205    233    2852            -           2606    16893    goods goods_g_group_fkey    FK CONSTRAINT     ~   ALTER TABLE ONLY public.goods
    ADD CONSTRAINT goods_g_group_fkey FOREIGN KEY (g_group) REFERENCES public.goods_groups(id);
 B   ALTER TABLE ONLY public.goods DROP CONSTRAINT goods_g_group_fkey;
       public       postgres    false    213    2830    215            ,           2606    16873 %   goods_groups goods_groups_parent_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.goods_groups
    ADD CONSTRAINT goods_groups_parent_fkey FOREIGN KEY (parent) REFERENCES public.goods_groups(id);
 O   ALTER TABLE ONLY public.goods_groups DROP CONSTRAINT goods_groups_parent_fkey;
       public       postgres    false    213    213    2830            4           2606    17002    incgoods incgoods_goods_fkey    FK CONSTRAINT     y   ALTER TABLE ONLY public.incgoods
    ADD CONSTRAINT incgoods_goods_fkey FOREIGN KEY (goods) REFERENCES public.goods(id);
 F   ALTER TABLE ONLY public.incgoods DROP CONSTRAINT incgoods_goods_fkey;
       public       postgres    false    215    2832    226            3           2606    16997    incgoods incgoods_id_fkey    FK CONSTRAINT     t   ALTER TABLE ONLY public.incgoods
    ADD CONSTRAINT incgoods_id_fkey FOREIGN KEY (id) REFERENCES public.income(id);
 C   ALTER TABLE ONLY public.incgoods DROP CONSTRAINT incgoods_id_fkey;
       public       postgres    false    211    226    2828            *           2606    16850    income income_client_fkey    FK CONSTRAINT     y   ALTER TABLE ONLY public.income
    ADD CONSTRAINT income_client_fkey FOREIGN KEY (client) REFERENCES public.clients(id);
 C   ALTER TABLE ONLY public.income DROP CONSTRAINT income_client_fkey;
       public       postgres    false    205    211    2822            +           2606    16855    income income_storage_fkey    FK CONSTRAINT     |   ALTER TABLE ONLY public.income
    ADD CONSTRAINT income_storage_fkey FOREIGN KEY (storage) REFERENCES public.storages(id);
 D   ALTER TABLE ONLY public.income DROP CONSTRAINT income_storage_fkey;
       public       postgres    false    207    211    2824            ;           2606    17383    irlink irlink_goods_fkey    FK CONSTRAINT     u   ALTER TABLE ONLY public.irlink
    ADD CONSTRAINT irlink_goods_fkey FOREIGN KEY (goods) REFERENCES public.goods(id);
 B   ALTER TABLE ONLY public.irlink DROP CONSTRAINT irlink_goods_fkey;
       public       postgres    false    215    2832    231            9           2606    17373    irlink irlink_i_id_fkey    FK CONSTRAINT     t   ALTER TABLE ONLY public.irlink
    ADD CONSTRAINT irlink_i_id_fkey FOREIGN KEY (i_id) REFERENCES public.income(id);
 A   ALTER TABLE ONLY public.irlink DROP CONSTRAINT irlink_i_id_fkey;
       public       postgres    false    211    2828    231            :           2606    17378    irlink irlink_r_id_fkey    FK CONSTRAINT     t   ALTER TABLE ONLY public.irlink
    ADD CONSTRAINT irlink_r_id_fkey FOREIGN KEY (r_id) REFERENCES public.recept(id);
 A   ALTER TABLE ONLY public.irlink DROP CONSTRAINT irlink_r_id_fkey;
       public       postgres    false    2826    231    209            (           2606    16832    recept recept_client_fkey    FK CONSTRAINT     y   ALTER TABLE ONLY public.recept
    ADD CONSTRAINT recept_client_fkey FOREIGN KEY (client) REFERENCES public.clients(id);
 C   ALTER TABLE ONLY public.recept DROP CONSTRAINT recept_client_fkey;
       public       postgres    false    209    205    2822            )           2606    16837    recept recept_storage_fkey    FK CONSTRAINT     |   ALTER TABLE ONLY public.recept
    ADD CONSTRAINT recept_storage_fkey FOREIGN KEY (storage) REFERENCES public.storages(id);
 D   ALTER TABLE ONLY public.recept DROP CONSTRAINT recept_storage_fkey;
       public       postgres    false    2824    209    207            6           2606    17015    recgoods recgoods_goods_fkey    FK CONSTRAINT     y   ALTER TABLE ONLY public.recgoods
    ADD CONSTRAINT recgoods_goods_fkey FOREIGN KEY (goods) REFERENCES public.goods(id);
 F   ALTER TABLE ONLY public.recgoods DROP CONSTRAINT recgoods_goods_fkey;
       public       postgres    false    2832    215    227            5           2606    17010    recgoods recgoods_id_fkey    FK CONSTRAINT     t   ALTER TABLE ONLY public.recgoods
    ADD CONSTRAINT recgoods_id_fkey FOREIGN KEY (id) REFERENCES public.recept(id);
 C   ALTER TABLE ONLY public.recgoods DROP CONSTRAINT recgoods_id_fkey;
       public       postgres    false    227    2826    209            7           2606    17251    remains remains_goods_fkey    FK CONSTRAINT     w   ALTER TABLE ONLY public.remains
    ADD CONSTRAINT remains_goods_fkey FOREIGN KEY (goods) REFERENCES public.goods(id);
 D   ALTER TABLE ONLY public.remains DROP CONSTRAINT remains_goods_fkey;
       public       postgres    false    228    215    2832            8           2606    17256    remains remains_storage_fkey    FK CONSTRAINT     ~   ALTER TABLE ONLY public.remains
    ADD CONSTRAINT remains_storage_fkey FOREIGN KEY (storage) REFERENCES public.storages(id);
 F   ALTER TABLE ONLY public.remains DROP CONSTRAINT remains_storage_fkey;
       public       postgres    false    207    2824    228            2           2606    16989    supply supply_storage_fkey    FK CONSTRAINT     |   ALTER TABLE ONLY public.supply
    ADD CONSTRAINT supply_storage_fkey FOREIGN KEY (storage) REFERENCES public.storages(id);
 D   ALTER TABLE ONLY public.supply DROP CONSTRAINT supply_storage_fkey;
       public       postgres    false    225    207    2824            �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �   T  x�]�ˍA�s�8 ��d}|��e� �"7��_�Vbl�������TU�����{��O�qM�J�_q�?�_�Ǐx�/�����3�?�b5��pM�Z��8�.n��/�����G�>^�)^xfr�)~2���!u)�����.�0υ�-�\�(��\i �|�8#�s����2Xi����~�,hr��mJ�9� �͊��ޭ�Ŋȑ��Б�VĎ|�<�J�ȯVD�|����B��_���nU��oVE�|�=�U�����8K���F�W�����P��+{�D_��&z�gk�G>V��R�D_��&z�#Q�ȇK�o�o�׉o��G����qr\��o�}��E�콋�p���\�N}�S���e�蝯l=�Q���w�;��.�N}}��w�#ǋ�ņ�;�~�������~�����G>J�G~�!��;g�~��C������~�~𭝢�O�.of�#%�#����~��X%�ɹ��G~�%�I���~�~R�D?99Ko{���䝳D��_�_�/�/N�����M� �㱉ߪM |Q6y�u|�6y�5��d���>Z~�`fO2�=      �   �   x�}�1�@E�SpA/�	8�`�vvjbgC����
n��������?1��	&)��b�	�
#z�^YnR��[9��B��)��	a(�Ⴓ��r6�E���g{J8�ٿ�(�TG+upl�;"���=FmYS��yD��a�40DZ�jU���W(�b��-u��      �   �   x�e��n�@D뻯X�6V���/��HRJ����
#H�J�Ԗ�8���?b�
(�6w;;o&5��#�:�'�^�p�� :G�
G�Ƒ�w"���%�X������#�e������5.����IK]4��~Lj�6�ux����,pN��≉%5T.)���x �e�Wf���uz��ad�i��xG��b���~��.�tQ(��Xk/2�n      �   �   x�]�MJA��]�h��Гq����ppB���g�E]�;���11�^�(�ɦ��^��uE.r�`��:�Q�q#5Ӧ(4�1˺K\,�5�Q�����?�ȥ�9|�Ԍ�RG|)�$Hb�mͱ��t�jw��t�C�`�1/�"XW�
����x����/]ar,�,R?q�5�Z�v�!}�z|1�?r�c�x�[gg���m����� ���WE�]��[      �   �   x�]�=�P���Sx@���à��3y��AHHg����(,,��v�2C����0b`�`��sC'��'k����f�"�N��Q����~�q����	�Fe��`�_/�*�Oƽj�[[��Ӗ^���)c�      �   H   x�M���0���0����j��2#�R� ��'��˂�B�)�f��o�����5\񷩶=���j�      �   ?   x�Eȱ !�������^�7\��u(���/���궽N$�˻l��Lx��D� �7�      �   !   x�3�4�4bs ij�e���\�=... N�Y      �   6   x�E�� �w�s�3�E�u�e�۠P�p�g�C0�{BN����2�]I�lL      �   R   x�U���@��2��p=t��C�\L_�Bݑ�Fd�z����/�Ĭmzm�
�9���"�f���V�q�}��1�X      �   �   x�u���0D��*� H��q�#HHHܐ���$Įa�#ƾp�a�z�3�;�6��ek��GĤn�zu�N[��<!���Rq��eۨӳ���,�=>K����/��X�cE�@�|�0#�)/Ymi�`��
�h��~��      �       x�3�4�4aCK]c]3N3�=... 8��      �   |   x�M���@�*����"@r@������~Z�k�J�7	���f���<����;W�DT�?7��9��,��x���ț�Ѷtʋ����*�����L�&�I��'�����m�KY"�yKY�      �      x������ � �      �      x�3�45�2�440������ z(     