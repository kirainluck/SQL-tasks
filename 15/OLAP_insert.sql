insert into sales_date (ddate)
select distinct ddate from recept;

insert into purchase_date (ddate)
select distinct ddate from income;

insert into remains_date (ddate)
select distinct ddate from remains;

insert into sales_storage (id, name, active)
select id, name, active from storages where id in
(select distinct storage from recept);

insert into purchase_storage (id, name, active)
select id, name, active from storages where id in
(select distinct storage from income);

insert into remains_storage (id, name, active)
select id, name, active from storages where id in
(select distinct storage from remains);

insert into sales_goods(id, name, g_group, weight, length, height, width, vol)
select id, name, g_group, weight, length, height, width, length*height*width 
from goods where id in (select distinct goods from recgoods);

insert into purchase_goods(id, name, g_group, weight, length, height, width, vol)
select id, name, g_group, weight, length, height, width, length*height*width 
from goods where id in (select distinct goods from incgoods);

insert into remains_goods(id, name, g_group, weight, length, height, width, vol)
select id, name, g_group, weight, length, height, width, length*height*width 
from goods where id in (select distinct goods from remains);

insert into sales_clients(id, name, address, city, client_groups, region)
select clients.id, clients.name, clients.address, clients.city,
clients.client_groups, city.region from clients
join city on city.id = clients.city
where clients.id in (select distinct client from recept);

insert into purchase_clients(id, name, address, city, client_groups, region)
select clients.id, clients.name, clients.address, clients.city,
clients.client_groups, city.region from clients
join city on city.id = clients.city
where clients.id in (select distinct client from income);


insert into purchase_fact_table(amount, quantity, volume,
							   weight, ddate_id, client_id, storage_id, goods_id)
select incgoods.volume*incgoods.price as amount,
incgoods.volume as quantity,
goods.height*goods.width*goods.length*incgoods.volume as volume,
goods.weight*incgoods.volume as weight,
purchase_date.id, purchase_clients.id, purchase_storage.id, purchase_goods.id
from incgoods
join income on income.id = incgoods.id
join goods on goods.id = incgoods.goods
join purchase_date on purchase_date.ddate = income.ddate
join purchase_clients on purchase_clients.id = income.client
join purchase_storage on purchase_storage.id = income.storage
join purchase_goods on purchase_goods.id = incgoods.goods;


insert into remains_fact_table(amount, quantity, volume,
							   weight, ddate_id, storage_id, goods_id)

select incgoods.price*rem_vols.vol as amount, rem_vols.vol as count,
goods.height*goods.width*goods.length*rem_vols.vol as volume,
goods.weight*rem_vols.vol as weight,
remains_date.id, remains_storage.id, remains_goods.id
from remains join goods on goods.id = remains.goods
join 
(
select rem.id, rem.subid, rem.goods, (rem.vol-irlink.volume) as vol from
(select id, subid, goods, sum(volume) as vol from remains
group by id, subid, goods) rem
join irlink on (irlink.i_id = rem.id and irlink.i_subid = rem.subid 
				and irlink.goods = rem.goods)) rem_vols
on (remains.id = rem_vols.id and remains.subid = rem_vols.subid
   and remains.goods = rem_vols.goods)
join incgoods on (incgoods.id = rem_vols.id and incgoods.subid = rem_vols.subid
				 and incgoods.goods = rem_vols.goods)
join remains_date on remains_date.ddate = remains.ddate
join remains_storage on remains_storage.id = remains.storage
join remains_goods on remains_goods.id = remains.goods;

insert into sales_fact_table(amount, quantity, volume,
							   weight, cost_price, ddate_id, client_id, storage_id, goods_id)
select recgoods.volume*recgoods.price as amount,
recgoods.volume as quantity,
goods.height*goods.width*goods.length*recgoods.volume as volume,
goods.weight*recgoods.volume as weight, cst.cost_price,
sales_date.id, sales_clients.id, sales_storage.id, sales_goods.id
from recgoods
join recept on recept.id = recgoods.id
join goods on goods.id = recgoods.goods
join
(
select goods, sum(price)/sum(volume)::real as cost_price from incgoods
group by goods) cst
on cst.goods = recgoods.goods
join sales_date on sales_date.ddate = recept.ddate
join sales_clients on sales_clients.id = recept.client
join sales_storage on sales_storage.id = recept.storage
join sales_goods on sales_goods.id = recgoods.goods;


