use warehouse_management;

# when insert, update, delete a inventory record, the trigger will automatically re-calculate the utilization of the location
drop trigger if exists update_utilization_insert_inventory;
delimiter $$
create trigger update_utilization_insert_inventory
after insert on inventory
for each row
begin

update locations
set utilization=location_utilization(new.warehouse_id,new.storage_location)
where warehouse_id=new.warehouse_id and location=new.storage_location;

end $$
delimiter ;



drop trigger if exists update_utilization_update_inventory;
delimiter $$
create trigger update_utilization_update_inventory
after update on inventory
for each row
begin

update locations
set utilization=location_utilization(new.warehouse_id,new.storage_location)
where warehouse_id=new.warehouse_id and location=new.storage_location;

end $$
delimiter ;



drop trigger if exists update_utilization_delete_inventory;
delimiter $$
create trigger update_utilization_delete_inventory
after delete on inventory
for each row
begin

update locations
set utilization=location_utilization(old.warehouse_id,old.storage_location)
where warehouse_id=old.warehouse_id and location=old.storage_location;

end $$
delimiter ;



# prevent invalid inventory, that is, the storage location's capacity is not enough
drop trigger if exists prevent_storage_overflow;
delimiter $$
create trigger prevent_storage_overflow
before insert on inventory
for each row
begin
declare location_capacity decimal(12,4);
declare location_utilization decimal(12,4);
declare product_volume decimal(8,2);
declare new_volume decimal(12,4);

# get location capacity info
select capacity, utilization into location_capacity,location_utilization
from locations
where warehouse_id=new.warehouse_id and location=new.storage_location;

# get product volume
select volume into product_volume
from products
where product_id = new.product_id;

# calculate volume of new items
set new_volume = new.total_quantity * product_volume;

# check if exceeds capacity
if (location_utilization+new_volume)>location_capacity then
signal sqlstate '45001'
set message_text = 'Error: Location capacity is not enough, insertion rejected';
end if;

end $$
delimiter ;



# employee cannot operate the inbound and outbound not in the warehouse he belongs to
drop trigger if exists check_inbound_operator_permission;
delimiter $$
create trigger check_inbound_operator_permission
before insert on inbound_orders
for each row
begin
declare employee_warehouse_id int;

select warehouse_id into employee_warehouse_id from employees where employee_id = new.operator;

if employee_warehouse_id != new.warehouse_id then
signal sqlstate '45002'
set message_text = 'Error: Operator does not belong to this warehouse';
end if;

end $$
delimiter ;



drop trigger if exists check_outbound_operator_permission;
delimiter $$
create trigger check_outbound_operator_permission
before insert on outbound_orders
for each row
begin
declare picker_warehouse_id int;
declare packer_warehouse_id int;

select warehouse_id into picker_warehouse_id from employees where employee_id = new.picker;
select warehouse_id into packer_warehouse_id from employees where employee_id = new.packer;

if picker_warehouse_id != new.warehouse_id or packer_warehouse_id != new.warehouse_id then
signal sqlstate '45002'
set message_text = 'Error: Operator does not belong to this warehouse';
end if;

end $$
delimiter ;



drop table if exists inbound_delay_alerts;
create table inbound_delay_alerts(
    alert_id bigint auto_increment primary key,
    inbound_id bigint not null,
    reference_number varchar(100),
    warehouse_id int,
    product_id int,
    delay_days int,
    alert_level enum('warning', 'critical') default 'warning',
    alert_message varchar(500),
    created_at datetime default now(),
    index idx_inbound_id (inbound_id),
    index idx_created_at (created_at),
    foreign key (inbound_id) references inbound_orders(inbound_id) on delete cascade,
    foreign key (warehouse_id) references warehouses(warehouse_id) on delete set null,
    foreign key (product_id) references products(product_id) on delete set null
);

drop trigger if exists inbound_delay_warning;
delimiter $$
create trigger inbound_delay_warning
after update on inbound_orders
for each row
begin
    declare v_delay_days int;
    declare v_alert_level varchar(20);
    declare v_alert_message varchar(500);
    declare existing_alert_id bigint;
    declare v_order_date datetime;
    declare v_reference varchar(100);
    set v_reference = concat(new.inbound_type, '-', new.inbound_id);
    set v_order_date = new.created_time;
    
    if new.status in ('pending', 'receiving') then
        set v_delay_days = datediff(now(), v_order_date);
        select alert_id into existing_alert_id 
        from inbound_delay_alerts 
        where inbound_id = new.inbound_id
        limit 1;
        
        if v_delay_days > 5 then
            if v_delay_days > 10 then
                set v_alert_level = 'critical';
                set v_alert_message = concat('critical: inbound order ', v_reference, ' delayed for ', v_delay_days, ' days. contact supplier immediately!');
            else
                set v_alert_level = 'warning';
                set v_alert_message = concat('warning: inbound order ', v_reference, ' delayed for ', v_delay_days, ' days. follow up required.');
            end if;
            
            -- Update alert if exist, create if not exist
            if existing_alert_id is not null then
                update inbound_delay_alerts 
                set delay_days = v_delay_days, alert_level = v_alert_level, alert_message = v_alert_message, created_at = now()
                where alert_id = existing_alert_id;
            else
                insert into inbound_delay_alerts(inbound_id, reference_number, warehouse_id, product_id, delay_days, alert_level, alert_message)
                values(new.inbound_id, v_reference, new.warehouse_id, new.product_id, v_delay_days, v_alert_level, v_alert_message);
            end if;
        end if;
        
    -- Delete alert if completed or cancelled
    elseif new.status in ('completed', 'cancelled') then
        delete from inbound_delay_alerts where inbound_id = new.inbound_id;
    end if;
end$$
delimiter ;



drop table if exists outbound_delay_alerts;
create table outbound_delay_alerts(
    alert_id bigint auto_increment primary key,
    outbound_id bigint not null,
    reference_number varchar(100),
    warehouse_id int,
    product_id int,
    delay_days int,
    alert_level enum('warning', 'critical') default 'warning',
    alert_message varchar(500),
    created_at datetime default now(),
    index idx_outbound_id (outbound_id),
    index idx_created_at (created_at),
    foreign key (outbound_id) references outbound_orders(outbound_id) on delete cascade,
    foreign key (warehouse_id) references warehouses(warehouse_id) on delete set null,
    foreign key (product_id) references products(product_id) on delete set null
);

drop trigger if exists outbound_delay_warning;
delimiter $$
create trigger outbound_delay_warning
after update on outbound_orders
for each row
begin
    declare v_delay_days int;
    declare v_alert_level varchar(20);
    declare v_alert_message varchar(500);
    declare existing_alert_id bigint;
    declare v_reference varchar(100);
    set v_reference = concat(new.outbound_type, '-', new.outbound_id);
    
    if new.status in ('pending', 'picking', 'packing') then
        set v_delay_days = datediff(now(), new.created_time);
        select alert_id into existing_alert_id 
        from outbound_delay_alerts 
        where outbound_id = new.outbound_id
        limit 1;

        if v_delay_days > 3 then
            if v_delay_days > 7 then
                set v_alert_level = 'critical';
                set v_alert_message = concat('critical: outbound order ', v_reference, ' delayed for ', v_delay_days, ' days. immediate action required!');
            else
                set v_alert_level = 'warning';
                set v_alert_message = concat('warning: outbound order ', v_reference, ' delayed for ', v_delay_days, ' days.');
            end if;
            
            -- Update alert if exist, create if not exist
            if existing_alert_id is not null then
                update outbound_delay_alerts 
                set delay_days = v_delay_days, alert_level = v_alert_level, alert_message = v_alert_message, created_at = now()
                where alert_id = existing_alert_id;
            else
                insert into outbound_delay_alerts(outbound_id, reference_number, warehouse_id, product_id, delay_days, alert_level, alert_message)
                values(new.outbound_id, v_reference, new.warehouse_id, new.product_id, v_delay_days, v_alert_level, v_alert_message);
            end if;
        end if;
        
    -- Delete alert if shipped or cancelled
    elseif new.status in ('shipped', 'cancelled') then
        delete from outbound_delay_alerts where outbound_id = new.outbound_id;
    end if;
end$$
delimiter ;