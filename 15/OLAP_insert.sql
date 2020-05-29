INSERT INTO sales_date (ddate) 
SELECT 
  DISTINCT ddate 
FROM 
  recept;
INSERT INTO purchase_date (ddate) 
SELECT 
  DISTINCT ddate 
FROM 
  income;
INSERT INTO remains_date (ddate) 
SELECT 
  DISTINCT ddate 
FROM 
  remains;
  
  
INSERT INTO sales_storage (id, name, active) 
SELECT 
  id, 
  name, 
  active 
FROM 
  storages 
WHERE 
  id IN (
    SELECT 
      DISTINCT STORAGE 
    FROM 
      recept
  );
  
  
INSERT INTO purchase_storage (id, name, active) 
SELECT 
  id, 
  name, 
  active 
FROM 
  storages 
WHERE 
  id IN (
    SELECT 
      DISTINCT STORAGE 
    FROM 
      income
  );
  
  
INSERT INTO remains_storage (id, name, active) 
SELECT 
  id, 
  name, 
  active 
FROM 
  storages 
WHERE 
  id IN (
    SELECT 
      DISTINCT STORAGE 
    FROM 
      remains
  );
  
  
INSERT INTO sales_goods(
  id, name, g_group, weight, LENGTH, height, 
  width, vol
) 
SELECT 
  id, 
  name, 
  g_group, 
  weight, 
  LENGTH, 
  height, 
  width, 
  LENGTH * height * width 
FROM 
  goods 
WHERE 
  id IN (
    SELECT 
      DISTINCT goods 
    FROM 
      recgoods
  );
  
  
INSERT INTO purchase_goods(
  id, name, g_group, weight, LENGTH, height, 
  width, vol
) 
SELECT 
  id, 
  name, 
  g_group, 
  weight, 
  LENGTH, 
  height, 
  width, 
  LENGTH * height * width 
FROM 
  goods 
WHERE 
  id IN (
    SELECT 
      DISTINCT goods 
    FROM 
      incgoods
  );
  
  
INSERT INTO remains_goods(
  id, name, g_group, weight, LENGTH, height, 
  width, vol
) 
SELECT 
  id, 
  name, 
  g_group, 
  weight, 
  LENGTH, 
  height, 
  width, 
  LENGTH * height * width 
FROM 
  goods 
WHERE 
  id IN (
    SELECT 
      DISTINCT goods 
    FROM 
      remains
  );
  
  
INSERT INTO sales_clients(
  id, name, address, city, client_groups, 
  region
) 
SELECT 
  clients.id, 
  clients.name, 
  clients.address, 
  clients.city, 
  clients.client_groups, 
  city.region 
FROM 
  clients 
  JOIN city ON city.id = clients.city 
WHERE 
  clients.id IN (
    SELECT 
      DISTINCT client 
    FROM 
      recept
  );
  
  
INSERT INTO purchase_clients(
  id, name, address, city, client_groups, 
  region
) 
SELECT 
  clients.id, 
  clients.name, 
  clients.address, 
  clients.city, 
  clients.client_groups, 
  city.region 
FROM 
  clients 
  JOIN city ON city.id = clients.city 
WHERE 
  clients.id IN (
    SELECT 
      DISTINCT client 
    FROM 
      income
  );
  
  
INSERT INTO purchase_fact_table(
  amount, quantity, volume, weight, ddate_id, 
  client_id, storage_id, goods_id
) 
SELECT 
  incgoods.volume * incgoods.price AS amount, 
  incgoods.volume AS quantity, 
  goods.height * goods.width * goods.length * incgoods.volume AS volume, 
  goods.weight * incgoods.volume AS weight, 
  purchase_date.id, 
  purchase_clients.id, 
  purchase_storage.id, 
  purchase_goods.id 
FROM 
  incgoods 
  JOIN income ON income.id = incgoods.id 
  JOIN goods ON goods.id = incgoods.goods 
  JOIN purchase_date ON purchase_date.ddate = income.ddate 
  JOIN purchase_clients ON purchase_clients.id = income.client 
  JOIN purchase_storage ON purchase_storage.id = income.storage 
  JOIN purchase_goods ON purchase_goods.id = incgoods.goods;
  
  
INSERT INTO remains_fact_table(
  amount, quantity, volume, weight, ddate_id, 
  storage_id, goods_id
) 
SELECT 
  incgoods.price * rem_vols.vol AS amount, 
  rem_vols.vol AS COUNT, 
  goods.height * goods.width * goods.length * rem_vols.vol AS volume, 
  goods.weight * rem_vols.vol AS weight, 
  remains_date.id, 
  remains_storage.id, 
  remains_goods.id 
FROM 
  remains 
  JOIN goods ON goods.id = remains.goods 
  JOIN (
    SELECT 
      rem.id, 
      rem.subid, 
      rem.goods, 
      (rem.vol - irlink.volume) AS vol 
    FROM 
      (
        SELECT 
          id, 
          subid, 
          goods, 
          sum(volume) AS vol 
        FROM 
          remains 
        GROUP BY 
          id, 
          subid, 
          goods
      ) rem 
      JOIN irlink ON (
        irlink.i_id = rem.id 
        AND irlink.i_subid = rem.subid 
        AND irlink.goods = rem.goods
      )
  ) rem_vols ON (
    remains.id = rem_vols.id 
    AND remains.subid = rem_vols.subid 
    AND remains.goods = rem_vols.goods
  ) 
  JOIN incgoods ON (
    incgoods.id = rem_vols.id 
    AND incgoods.subid = rem_vols.subid 
    AND incgoods.goods = rem_vols.goods
  ) 
  JOIN remains_date ON remains_date.ddate = remains.ddate 
  JOIN remains_storage ON remains_storage.id = remains.storage 
  JOIN remains_goods ON remains_goods.id = remains.goods;
  
  
INSERT INTO sales_fact_table(
  amount, quantity, volume, weight, cost_price, 
  ddate_id, client_id, storage_id, 
  goods_id
) 
SELECT 
  recgoods.volume * recgoods.price AS amount, 
  recgoods.volume AS quantity, 
  goods.height * goods.width * goods.length * recgoods.volume AS volume, 
  goods.weight * recgoods.volume AS weight, 
  cst.cost_price, 
  sales_date.id, 
  sales_clients.id, 
  sales_storage.id, 
  sales_goods.id 
FROM 
  recgoods 
  JOIN recept ON recept.id = recgoods.id 
  JOIN goods ON goods.id = recgoods.goods 
  JOIN (
    SELECT 
      goods, 
      sum(price)/ sum(volume):: real AS cost_price 
    FROM 
      incgoods 
    GROUP BY 
      goods
  ) cst ON cst.goods = recgoods.goods 
  JOIN sales_date ON sales_date.ddate = recept.ddate 
  JOIN sales_clients ON sales_clients.id = recept.client 
  JOIN sales_storage ON sales_storage.id = recept.storage 
  JOIN sales_goods ON sales_goods.id = recgoods.goods;
