
begin;

--  select time, height,hash from leaves l join block_ b on b.id = l.id ;
--  select time, height,hash from leaves l join block_ b on b.id = l.id order by height desc;

-- important chainstate projection to tx ought to be easy, we just
-- create a view of tx's that are the mainchain only, and use that
-- for all the received, unspent etc.

-- we can also always store the height manually, rather than compute dynamically. may not be bad...
------------

-- ok, it would be nice to test for speed etc by populating just the blocks table ...
-- including orphans and then test out these functions...

-- TODO change name to _leaves
create or replace view leaves as
select
  b.hash as b,
  pb.hash as pb,
  pb.id
from block b
-- should reorder to left join...
right join block pb on pb.id = b.previous_id
where b.id is null
;

-- a view of the block table including height

drop view if exists _leaves2 ; 
drop view if exists block_ ; 

-- change name _block
create or replace view block_ as
with recursive t( id, height ) AS (
  select (select id from block where previous_id is null), 0
  UNION ALL
  SELECT block.id, t.height + 1
  FROM block
  join t on t.id = block.previous_id
)
select t.height, block.* 
FROM t join block on block.id = t.id;


-- could return more than one entry...

-- select * from block_ where
-- height = (SELECT max(height) FROM block_ ) ; 

create or replace view _leaves2 as
select 
  now() - time as when, 
  time, 
  height,
  hash,
  b.id as block_id
from leaves l 
join block_ b on b.id = l.id 
order by height desc;

commit;

