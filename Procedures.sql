use warehouse_management;

drop procedure if exists split_inventory;
delimiter $$
create procedure split_inventory(
In sourceid bigint, # which inventory will be split
In qty int, # quantity
In operatorid int,
In toware int, # to which warehouse, -1 for drop all
In newlocation varchar(100)
)
begin
# store the old data in the inventory for updating the log, which is "inventory_adjustments"
declare old_total int;
declare old_product_id int;
declare old_warehouse_id int;
declare old_unit varchar(20);
declare old_loc varchar(100);
declare old_prod date;
declare old_exp date;
declare new_inventory_id bigint;
declare new_adjustment_id1 bigint;
declare new_adjustment_id2 bigint;
    
select total_quantity,product_id,warehouse_id,unit,storage_location,production_date,expiry_date
into old_total,old_product_id,old_warehouse_id,old_unit,old_loc,old_prod,old_exp
from inventory
where inventory_id=sourceid;
	
# drop all the inventory
if toware=-1 then
select ifnull(max(adjustment_id1),0)+1 into new_adjustment_id1 from inventory_adjustments; # get the maximum number+1 to be the new adjustment_id
#update the log
insert into inventory_adjustments(
adjustment_id,adjustment_type,warehouse_id,product_id,inventory_id,
before_quantity,after_quantity,quantity_change,
adjustment_reason,operator
)
values(
new_adjustment_id1,'write off',old_warehouse_id,old_product_id,sourceid,
old_total,0,-old_total,'inventory drop',operatorid
);

else
# split the inventory, one part goes to the other warehouse, and the rest remains there
update inventory
#update the quantity of the source inventory
set total_quantity=total_quantity-qty, 
available_quantity=available_quantity-qty
where inventory_id=sourceid;

#generate new ids
select ifnull(max(inventory_id),0)+1 into new_inventory_id from inventory;
select ifnull(max(adjustment_id),0)+1 into new_adjustment_id1 from inventory_adjustments;
set new_adjustment_id2=new_adjustment_id1+1;

insert into inventory(
inventory_id,product_id,warehouse_id,storage_location,
total_quantity,locked_quantity,available_quantity,
unit,production_date,expiry_date,parent_inventory_id
)
values(
new_inventory_id,old_product_id,toware,newlocation,qty,0,qty,
old_unit,old_prod,old_exp,sourceid
);

#update the log
insert into inventory_adjustments(
adjustment_id,adjustment_type,warehouse_id,product_id,inventory_id,
before_quantity,after_quantity,quantity_change,adjustment_reason,operator
)
values(
new_adjustment_id1,'split',toware,old_product_id,new_inventory_id,0,qty,qty,concat('split from ',sourceid),operatorid
);
insert into inventory_adjustments(
adjustment_id,adjustment_type,warehouse_id,product_id,inventory_id,
before_quantity,after_quantity,quantity_change,adjustment_reason,operator
)
values(
new_adjustment_id2,'split',old_warehouse_id,old_product_id,sourceid,
old_total,old_total-qty,-qty,concat('split to ',new_inventory_id),operatorid
);
end if;
end$$
delimiter ;


#calculate the space utilization for all locations, use the function before
drop procedure if exists calculate_utilization;
delimiter $$
create procedure calculate_utilization()
begin
declare warehouseid bigint;
declare location_ varchar(100);
declare done boolean default False;
declare cur cursor for select warehouse_id,location from locations;
declare continue handler for not found set done=True;

open cur;

cal: Loop
fetch cur into warehouseid,location_;

if done then leave cal; end if;

update locations
set utilization=location_utilization(warehouseid,location)
where warehouse_id=warehouseid and location=location_;

end loop cal;
close cur;
end $$
delimiter ;



drop procedure if exists create_inbound_order;
delimiter $$
create procedure create_inbound_order(
In typ varchar(20),
In productid int,
In warehouseid int,
In expected int,
In total_items int,
In operator int,
In notes text
)
begin
declare id bigint;

select max(inbound_id)+1 into id from inbound_orders;
insert into inbound_orders(inbound_id,product_id,inbound_type,warehouse_id,expected_quantity,total_items,status,operator,notes)
values(id,productid,typ,warehouseid,expected,total_items,'pending',operator,notes);

end$$
delimiter ;


drop procedure if exists complete_inbound;
delimiter $$
create procedure complete_inbound(
in inboundid bigint,
in actualqty int,
in newlocation varchar(100)
)
begin	
declare warehouseid int;
declare productid bigint;
declare id bigint;
declare inbound_exists int default 0;

select count(*) into inbound_exists
from inbound_orders
where inbound_id=inboundid;

select ifnull(max(inventory_id),0)+1 into id from inventory;
select warehouse_id,product_id into warehouseid,productid
from inbound_orders
where inbound_id=inboundid;
update inbound_orders
set status='completed',actual_quantity=actualqty,received_time=now()
where inbound_id=inboundid;
insert into inventory(inventory_id, product_id, warehouse_id, total_quantity, locked_quantity, available_quantity, inventory_status, last_updated,storage_location)
values(id,productid,warehouseid,actualqty,0,actualqty,'normal',now(),newlocation);

end$$
delimiter ;



drop procedure if exists create_outbound_order;
delimiter $$
create procedure create_outbound_order(
In typ varchar(20),
In productid bigint,
In warehouseid int,
In total_items int,
In total_qty int,
In picker int,
In packer int
)
begin
declare id bigint;
select max(outbound_id)+1 into id from outbound_orders;
insert into outbound_orders(outbound_id,outbound_type,warehouse_id,total_items,total_quantity,status,picker,packer,product_id)
values(id,typ,warehouseid,total_items,total_qty,'pending',picker,packer,productid);
end$$
delimiter ;



drop procedure if exists complete_outbound;
delimiter $$
create procedure complete_outbound(
In inv_id bigint,
In outboundid bigint
)
begin
declare avail int;
declare qty int;
declare outbound_exists int default 0;

select total_quantity into qty from outbound_orders where outbound_id=outboundid;

update outbound_orders
set status='shipped',
shipped_time=now()
where outbound_id=outboundid;
update inventory
set total_quantity=total_quantity-qty,available_quantity=available_quantity-qty,last_updated=now()
where inventory_id=inv_id;
end$$
delimiter ;



drop procedure if exists update_employee_status;
delimiter $$
create procedure update_employee_status(
    in p_employee_id int,
    in p_new_status enum('active', 'terminated', 'leave'),
    out p_result_message varchar(200)
)
begin
    declare v_current_status enum('active', 'terminated', 'leave');
    declare v_employee_exists boolean;
    select count(*) > 0 into v_employee_exists
    from employees 
    where employee_id = p_employee_id;
    
    if not v_employee_exists then
        set p_result_message = 'Error: Employee does not exist';
    else
        select employment_status into v_current_status
        from employees 
        where employee_id = p_employee_id;
        update employees 
        set employment_status = p_new_status
        where employee_id = p_employee_id;
        set p_result_message = concat('Change employee status form ', v_current_status, ' to ', p_new_status);
    end if;
end $$

delimiter ;

create table if not exists supplier_monthly_report(
    report_id bigint auto_increment primary key,
    report_month varchar(7),
    supplier_id int,
    supplier_name varchar(200),
    total_inbound decimal(12,4),
    return_count int,
    quality_score decimal(5,2),
    created_at datetime default now(),
    index idx_month_supplier (report_month, supplier_id)
);

drop procedure if exists supplier_monthly_report;
delimiter $$
create procedure supplier_monthly_report(
    in p_month varchar(7)  -- 'YYYY-MM'
)
begin
    declare start_date date;
    declare end_date date;
    declare record_count int default 0;
 
    if length(p_month) != 7 or p_month not regexp '^[0-9]{4}-[0-9]{2}$' then
        signal sqlstate '45000' set message_text = 'Invalid month format. Please use YYYY-MM';
    end if;

    set start_date = str_to_date(concat(p_month, '-01'), '%Y-%m-%d');
    set end_date = LAST_DAY(start_date);
    
    if start_date is null then
        signal sqlstate '45000' set message_text = 'Invalid date format';
    end if;
    
    delete from supplier_monthly_report where report_month = p_month;
    
    insert into supplier_monthly_report (report_month, supplier_id, supplier_name, total_inbound, return_count, quality_score)
    select p_month, s.supplier_id, s.supplier_name, coalesce(sum(case when io.status = 'completed' then io.actual_quantity else 0 end), 0) as total_inbound, coalesce(sum(case when io.inbound_type = 'return' and io.status = 'completed' then 1 else 0 end), 0) as return_count, case when count(io.inbound_id) = 0 then 100.00 else round((1 - sum(case when io.inbound_type = 'return' and io.status = 'completed' then 1 else 0 end) / count(case when io.status = 'completed' then 1 else null end)) * 100, 2) end as quality_score
    from suppliers s
    left join supplier_products sp on sp.supplier_id = s.supplier_id
    left join inbound_orders io on io.product_id = sp.product_id and io.status = 'completed' and io.received_time between start_date and end_date
    where s.status = 'active'
    group by s.supplier_id, s.supplier_name
    having total_inbound > 0 or return_count > 0;
    select row_count() into record_count;
    
    if record_count > 0 then
        select concat('Month: ', p_month) as period, concat('Records: ', record_count) as summary;
        select supplier_id as 'Supplier_ID', supplier_name as 'Supplier_Name', total_inbound as 'Total_Inbound', return_count as 'Return_Count', quality_score as 'Quality_Score'
        from supplier_monthly_report 
        where report_month = p_month
        order by total_inbound desc;
    else
        select 'No data found for the specified period' as message, concat('Month: ', p_month) as period, 'Please check if there are completed inbound orders for this month' as suggestion;
    end if;
end$$
delimiter ;