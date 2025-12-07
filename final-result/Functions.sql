Use warehouse_management;

#calculate the how much space has been used in a specific location
drop function if exists location_utilization;

delimiter $$
create function location_utilization(
warehouse_id bigint,
location varchar(100)
)
returns decimal(12,4)
deterministic
reads sql data
begin
declare utilization decimal(12,4) default 0;
select coalesce(sum(T.volume*S.total_quantity),0) into utilization
from products as T join inventory as S on T.product_id=S.product_id
where S.warehouse_id=warehouse_id and S.storage_location=location;
return utilization;
end $$
delimiter ;



drop function if exists is_employee_in_warehouse;
delimiter $$
create function is_employee_in_warehouse(
    p_employee_id int,
    p_warehouse_id int
) 
returns boolean
reads sql data
deterministic
begin
    declare v_result boolean default false;
    select count(*) > 0 into v_result
    from employees 
    where employee_id = p_employee_id 
    and warehouse_id = p_warehouse_id
    and employment_status = 'active';
    return v_result;
end $$
delimiter ;



drop function if exists sell_through_rate;
delimiter $$
create function sell_through_rate(p_product_id int)
returns text
deterministic
begin
    declare inboundqty decimal(12,4);
    declare soldqty decimal(12,4);
    declare rate decimal(10,2);
    declare result_text text;
    select ifnull(sum(actual_quantity), 0)
    into inboundqty
    from inbound_orders
	where status = 'completed'
      and product_id = p_product_id;
    select ifnull(sum(total_quantity), 0)
	into soldqty
    from outbound_orders
    where status = 'shipped'
      and product_id = p_product_id
      and outbound_type = 'sales';
    if inboundqty = 0 then
        set rate = 0;
        set result_text = concat('Sell-through rate: 0% (No inbound inventory - Inbound: ', inboundqty, ', Sales: ', soldqty, ')');
    else
        set rate = round((soldqty / inboundqty) * 100, 2);
        set result_text = concat('Sell-through rate: ', rate, '% (Inbound: ', inboundqty, ', Sales: ', soldqty, ')');
    end if;
    return result_text;
end$$
delimiter ;
