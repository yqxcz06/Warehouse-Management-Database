drop database if exists warehouse_management;
set foreign_key_checks=0;

create database warehouse_management;
use warehouse_management;

create table warehouses(
    warehouse_id int primary key,
    warehouse_name varchar(100) not null,
    warehouse_type enum('central', 'regional', 'front') not null,
    address text,
    contact_person varchar(50),
    phone_number varchar(50),
    status enum('active', 'inactive') default 'active',
    created_time datetime default current_timestamp
);

create table locations(
	warehouse_id int not null,
    location varchar(100) not null,
    capacity decimal(12,4) not null check (capacity>0),
    utilization decimal(12,4),
    primary key(warehouse_id, location),
    foreign key (warehouse_id) references warehouses(warehouse_id) on delete cascade,
    check (utilization<=capacity)
);

create table suppliers(
    supplier_id int primary key,
    supplier_name varchar(200) not null,
    contact_info text,
    supply_cycle int,
    status enum('active', 'inactive') default 'active'
);

create table products (
    product_id int primary key,
    product_sku varchar(50) unique not null,
    product_name varchar(200) not null,
    product_description text,
    category varchar(50),
    dimensions varchar(100),
    volume decimal(8,2),
    weight decimal(8,2),
    value decimal(10,2),
    packaging_info varchar(200),
    status enum('active', 'discontinued') default 'active'
);

create table supplier_products(
    supplier_id int,
    product_id int,
    supplier_sku varchar(50),
    supply_price decimal(10,2),
    min_order_quantity decimal(12,4),
    lead_time_days int,
    is_preferred boolean default false,
    created_time datetime default current_timestamp,
    last_updated datetime default current_timestamp,
    primary key (supplier_id, product_id),
    foreign key (supplier_id) references suppliers(supplier_id) on delete cascade,
    foreign key (product_id) references products(product_id) on delete cascade
);

create table employees(
    employee_id int primary key,
    employee_number varchar(20) unique not null,
    employee_name varchar(100) not null,
    department enum('warehouse_ops', 'order_processing', 'quality_control', 'system_admin') not null,
    position varchar(50),
    contact_phone varchar(50),
    email varchar(100),
    employment_status enum('active', 'terminated', 'leave') default 'active',
    warehouse_id int,
    created_time datetime default current_timestamp,
    foreign key (warehouse_id) references warehouses(warehouse_id) on delete set null
);

create table inventory(
    inventory_id bigint primary key,
    product_id int not null,
    warehouse_id int not null,
    storage_location varchar(100),
    total_quantity int default 0 check (total_quantity>=0),
    locked_quantity int default 0 check (locked_quantity>=0),
    available_quantity int default 0 check(available_quantity>=0),
    unit varchar(20) default 'pcs',
    production_date date,
    expiry_date date,
    inventory_status enum('normal', 'hold', 'quarantine') default 'normal',
    parent_inventory_id bigint,
    last_updated datetime default current_timestamp,
    foreign key (product_id) references products(product_id) on delete cascade,
    foreign key (warehouse_id) references warehouses(warehouse_id) on delete cascade,
    foreign key (warehouse_id, storage_location) references locations(warehouse_id, location) on update cascade on delete cascade,
    foreign key (parent_inventory_id) references inventory(inventory_id) on delete set null,
    check(total_quantity=locked_quantity+available_quantity)
);

create table inbound_orders(
    inbound_id bigint primary key,
    product_id int,
    inbound_type enum('purchase', 'transfer', 'return') not null,
    warehouse_id int not null,
    expected_quantity int check(expected_quantity>=0),
    actual_quantity int check(actual_quantity>=0),
    total_items int,
    status enum('pending', 'receiving', 'completed', 'cancelled') default 'pending',
    created_time datetime default current_timestamp,
    received_time datetime,
    operator int not null,
    notes text,
    foreign key (warehouse_id) references warehouses(warehouse_id) on delete cascade,
    foreign key (product_id) references products(product_id) on delete cascade,
    foreign key (operator) references employees(employee_id) on delete restrict
);

create table outbound_orders(
    outbound_id bigint primary key,
    product_id int,
    outbound_type enum('sales', 'transfer', 'return') not null,
    warehouse_id int not null,
    total_items int,
    total_quantity int,
    status enum('pending', 'picking', 'packing', 'shipped', 'cancelled') default 'pending',
    picker int,
    packer int,
    created_time datetime default current_timestamp,
    shipped_time datetime,
    foreign key (warehouse_id) references warehouses(warehouse_id) on delete cascade,
    foreign key (product_id) references products(product_id) on delete cascade,
    foreign key (picker) references employees(employee_id) on delete set null,
    foreign key (packer) references employees(employee_id) on delete set null
);

create table inventory_adjustments(
    adjustment_id bigint primary key,
    adjustment_type enum('count', 'transfer', 'write_off', 'split') not null,
    warehouse_id int not null,
    product_id int not null,
    inventory_id bigint not null,
    before_quantity int check(before_quantity>=0),
    after_quantity int check(after_quantity>=0),
    quantity_change int,
    adjustment_reason varchar(200),
    operator int,
    adjustment_time datetime default current_timestamp,
    notes text,
    foreign key (warehouse_id) references warehouses(warehouse_id) on delete cascade,
    foreign key (product_id) references products(product_id) on delete cascade,
    foreign key (inventory_id) references inventory(inventory_id) on delete cascade,
    foreign key (operator) references employees(employee_id) on delete restrict
);

set foreign_key_checks=1;
