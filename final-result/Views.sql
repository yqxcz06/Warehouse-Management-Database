use warehouse_management;

drop view if exists High_Value_Products_with_Poor_Selling;
# Find products with inventory value exceeding their category's average, and no shipped outbound orders in the past 3 months. (Poor selling products)
create view High_Value_Products_with_Poor_Selling as(
with product_sumvalue as(
select T.product_id, sum(T.value*S.total_quantity) as sumvalue
from products as T join inventory as S on T.product_id=S.product_id
group by T.product_id
),
category_avgvalue as(
select T.category, avg(Q.sumvalue) as avgvalue
from product_sumvalue as Q join products as T on Q.product_id=T.product_id
group by T.category
)
select T.product_name,T.product_id,T.category,S.avgvalue,Q.sumvalue
from products as T,category_avgvalue as S,product_sumvalue as Q
where Q.sumvalue>S.avgvalue and T.category=S.category and T.product_id=Q.product_id
and not exists(
select *
from outbound_orders as E
where T.product_id=E.product_id and E.status="shipped" and E.shipped_time>=date_sub(curdate(),interval 3 month)
)
order by T.product_id asc
);



drop view if exists high_writeoff_rate_warehouses;
# Find warehouses where the absolute write-off quantity loss exceeds 0.5% of total historical inbound actual quantity (classified as "high-loss").
create view high_writeoff_rate_warehouses as(
with white_off_quantity as(
select warehouse_id,abs(sum(quantity_change))as writeoff
from inventory_adjustments
where adjustment_type="write_off"
group by warehouse_id
),
total_quantity as(
select warehouse_id,sum(actual_quantity) as total_quantity
from inbound_orders
where status="completed" or status="receiving" and actual_quantity<>0
group by warehouse_id
)
select E.warehouse_id,E.warehouse_name,E.contact_person,T.writeoff,S.total_quantity
from white_off_quantity as T join total_quantity as S on T.warehouse_id=S.warehouse_id join warehouses as E on E.warehouse_id=T.warehouse_id
where T.writeoff/S.total_quantity>=0.005
);



drop view if exists misleading_suppliers;
# Identify the suppliers who are not performing up to par. 
# That is,The total number of inbound entries from a supplier that are flagged as 'return'
# exceeds 20% of the supplier's total inbound transactions (or documents).
create view misleading_suppliers as(
with total_inbound as(
select T.supplier_id,count(S.inbound_id) as inbound_times
from supplier_products as T left outer join inbound_orders as S on T.product_id=S.product_id
where T.is_preferred=True 
group by T.supplier_id
),
return_inbound as(
select T.supplier_id,count(S.inbound_id) as return_times
from supplier_products as T left outer join inbound_orders as S on T.product_id=S.product_id
where S.inbound_type="return" and T.is_preferred=True 
group by T.supplier_id
)
select T.supplier_id,T.supplier_name
from suppliers as T join total_inbound as S on T.supplier_id=S.supplier_id join return_inbound as Q on S.supplier_id=Q.supplier_id
where Q.return_times/S.inbound_times>0.2
);



drop view if exists get_warehouse_utilization;
create view get_warehouse_utilization as (
select T.warehouse_id,T.warehouse_name,sum(S.utilization) as warehouse_utilization,sum(S.capacity) as warehouse_capacity
from warehouses as T join locations as S on T.warehouse_id=S.warehouse_id
group by T.warehouse_id,T.warehouse_name
order by T.warehouse_id
);



drop view if exists inventory_value_by_product;
create view inventory_value_by_product as (
select T.product_id, T.product_name, T.product_sku, sum(T.value*S.total_quantity) as sumvalue
from products as T join inventory as S on T.product_id=S.product_id
group by T.product_id, T.product_name, T.product_sku
order by T.product_id
);



drop view if exists get_product_suppliers;
create view get_product_suppliers as(
select T.supplier_id,T.supplier_name,S.product_id
from suppliers as T join supplier_products as S on T.supplier_id=S.supplier_id
);



drop view if exists employee_details_view;
create view employee_details_view as (
select e.employee_id, e.employee_number, e.employee_name, e.department, e.position, e.contact_phone, e.email, e.employment_status, e.warehouse_id, w.warehouse_name, w.warehouse_type, w.address as warehouse_address, e.created_time
from employees e
left join warehouses w on e.warehouse_id = w.warehouse_id
where e.employment_status = 'active'
);



drop view if exists department_employee_stats_view;
create view department_employee_stats_view as (
select department, count(*) as total_employees, count(case when employment_status = 'active' then 1 end) as active_employees, count(case when employment_status = 'terminated' then 1 end) as terminated_employees, count(case when employment_status = 'leave' then 1 end) as on_leave_employees
from employees
group by department
);



drop view if exists warehouse_employee_distribution_view;
create view warehouse_employee_distribution_view as (
select w.warehouse_id, w.warehouse_name, w.warehouse_type, count(e.employee_id) as total_employees, count(case when e.department = 'warehouse_ops' then 1 end) as ops_employees, count(case when e.department = 'order_processing' then 1 end) as order_employees, count(case when e.department = 'quality_control' then 1 end) as quality_employees, count(case when e.department = 'system_admin' then 1 end) as admin_employees
from warehouses w
left join employees e on w.warehouse_id = e.warehouse_id and e.employment_status = 'active'
group by w.warehouse_id, w.warehouse_name, w.warehouse_type
);



drop view if exists employee_operation_stats_view;
create view employee_operation_stats_view as (
select e.employee_id, e.employee_name, e.department, w.warehouse_name, count(distinct io.inbound_id) as total_inbound_operations, count(distinct oo.outbound_id) as total_outbound_operations, count(distinct ia.adjustment_id) as total_adjustment_operations, coalesce(sum(io.actual_quantity), 0) as total_inbound_quantity, coalesce(sum(oo.total_quantity), 0) as total_outbound_quantity
from employees e
left join warehouses w on e.warehouse_id = w.warehouse_id
left join inbound_orders io on e.employee_id = io.operator
left join outbound_orders oo on (e.employee_id = oo.picker or e.employee_id = oo.packer)
left join inventory_adjustments ia on e.employee_id = ia.operator
where e.employment_status = 'active'
group by e.employee_id, e.employee_name, e.department, w.warehouse_name
);



drop view if exists supplier_products_detail_view;
create view supplier_products_detail_view as (
select s.supplier_id, s.supplier_name, s.status as supplier_status, sp.supplier_sku, sp.supply_price, sp.min_order_quantity, sp.lead_time_days, sp.is_preferred, sp.created_time as supply_relationship_created, sp.last_updated as supply_relationship_updated, p.product_id, p.product_sku, p.product_name, p.product_description, p.category, p.dimensions, p.volume, p.weight, p.value as product_market_value, round((p.value - sp.supply_price) / sp.supply_price * 100, 2) as profit_margin_percent, p.status as product_status    
from suppliers s
join supplier_products sp on s.supplier_id = sp.supplier_id
join products p on sp.product_id = p.product_id
where s.status = 'active' and p.status = 'active'
order by s.supplier_name, p.product_name
);
