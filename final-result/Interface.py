import mysql.connector
from mysql.connector import Error
import pandas as pd
import os
from decimal import Decimal


#this part is done by chatgpt,for the execution of files
os.chdir(os.path.dirname(os.path.abspath(__file__)))

db_conn = mysql.connector.connect(
    host="localhost",
    user="root",
    password="",
    autocommit=True
)
cursor = db_conn.cursor()

def run_sql_file(filename):
    with open(filename, "r", encoding="utf-8") as f:
        sql = f.read()

    statements = []
    delimiter = ";"
    buffer = ""

    for line in sql.splitlines():
        line_strip = line.strip()

        if line_strip.lower().startswith("delimiter"):
            delimiter = line_strip.split()[1]
            continue

        buffer += line + "\n"

        if line_strip.endswith(delimiter):
            stmt = buffer.rsplit(delimiter, 1)[0].strip()
            buffer = ""

            if stmt:
                try:
                    cursor.execute(stmt)
                    try:
                        while True:
                            cursor.fetchall()
                            if not cursor.nextset():
                                break
                    except:
                        pass
                except Exception as e:
                    print("Error:", e)

                    raise e

    if buffer.strip():
        cursor.execute(buffer)

print("Running Schema.sql ...")
run_sql_file("Schema.sql")
db_conn.database = "warehouse_management"

sql_files = [
    "Functions.sql",
    "Procedures.sql",
    "Views.sql",
    "Triggers.sql",
    "Insert_data_fixed.sql"
]

for file in sql_files:
    print(f"\nRunning {file} ...")
    run_sql_file(file)

print("\nAll SQL files executed successfully.")

def prints():
    output = cursor.fetchall()
    column = [s[0] for s in cursor.description] if cursor.description else []
    df = pd.DataFrame(output, columns=column) if output and column else pd.DataFrame(output)
    print(df)
    print("\n")
    return None
def printopt():
    s="""
    1.Warehouse
    1-1 List all warehouses
    1-2 Query warehouse utilization
    1-3 Warehouse inventory overview
    1-4 High writeoff rate warehouses
    1-5 Recalculate utilization

    2.Product & Supplier
    2-1 List all products
    2-2 Product supplier list
    2-3 Sell Through Rate
    2-4 Supplier monthly report
    2-5 Supplier product detail view
    2-6 High value but poor selling products
    2-7 Misleading suppliers

    3.Inventory
    3-1 Query inventory
    3-2 Split inventory
    3-3 Expiring items

    4.Inbound
    4-1 Create inbound order
    4-2 Complete inbound
    4-3 Inbound delay warnings

    5.Outbound
    5-1 Create outbound order
    5-2 Complete outbound
    5-3 Outbound delay warnings

    6.Employee
    6-1 Employee details
    6-2 Department stats
    6-3 Warehouse employee distribution
    6-4 Employee operation stats
    6-5 Check employee in warehouse
    6-6 Department employee count
    6-7 Update employee status

    7.Inventory Value
    7-1 Inventory value by product
    7-2 Inventory value by category

    8.Exit
    """
    print(s)

def press_enter():
    input("\n>>> Press Enter to continue...")
    #os.system("cls")

# 1-1 Qixuan Yuan
def list_warehouses(cursor):
    cursor.execute("select * from warehouses")
    prints()
    return None

# 1-2 Qixuan Yuan
def get_warehouse_utilization(cursor):
    cursor.execute("select * from warehouse_management.get_warehouse_utilization;")
    prints()
    return None

# 1-3 Shaoxiang Qu
def warehouse_inventory_overview(cursor, warehouse_id=None):
    sql = """
    select w.warehouse_id, w.warehouse_name,
    count(distinct i.product_id) as product_count,
    ifnull(sum(i.total_quantity * p.value),0) as inventory_value,
    ifnull(sum(i.total_quantity),0) as total_units
    from warehouses w
    left join inventory i on i.warehouse_id = w.warehouse_id
    left join products p on p.product_id = i.product_id
    {}
    group by w.warehouse_id, w.warehouse_name
    """.format("where w.warehouse_id = %s" if warehouse_id else "")
    if warehouse_id:
        cursor.execute(sql, (warehouse_id,))
    else:
        cursor.execute(sql)
    prints()
    return None

# 1-4 Qixuan Yuan
def high_writeoff_rate_warehouses():
    cursor.execute("select * from warehouse_management.high_writeoff_rate_warehouses;")
    prints()

# 1-5 Qixuan Yuan
def calculate_utilization():
    cursor.execute("call calculate_utilization();")

# 2-1 Qixuan Yuan
def list_products(cursor):
    cursor.execute("select product_id,product_sku,product_name,category from products order by product_id asc")
    prints()
    return None

# 2-2 Qixuan Yuan
def get_product_suppliers(cursor, product_id):
    cursor.execute("select * from get_product_suppliers where product_id={}".format(product_id))
    prints()
    return None

# 2-3 Shaoxiang Qu
def calculate_sell_through_rate(cursor, product_id):
    try:
        cursor.execute("select sell_through_rate(%s)", (int(product_id),))
        result = cursor.fetchone()
        
        if result and result[0] is not None:
            rate = result[0]
            cursor.execute("select product_name from products where product_id = %s", (int(product_id),))
            product_info = cursor.fetchone()
            product_name = product_info[0] if product_info else "Unknown Product"
            print(f"Product: {product_name}")
            print(f"{rate}")
            return True
        else:
            print(f"No data available for product ID: {product_id}")
            return False
            
    except ValueError:
        print("Error: Please enter a valid numeric Product ID")
        return False
    except Exception as e:
        print(f"Error calculating sell-through rate: {e}")
        return False

# 2-4 Shaoxiang Qu
def generate_supplier_monthly_report(cursor, month):
    if len(month) != 7 or not month.startswith('20'):
        print("Error: Please use valid format YYYY-MM (e.g., 2025-01)")
        return False
        
    try:
        cursor.callproc("supplier_monthly_report", (month,))
        results_processed = False
        
        for result in cursor.stored_results():
            rows = result.fetchall()
            columns = [desc[0] for desc in result.description] if result.description else []
            
            if rows:
                if len(columns) == 3:
                    print(f"\n{rows[0][0]}")
                    for row in rows:
                        print(f"{row[1]}: {row[2]}")
                else:
                    df = pd.DataFrame(rows, columns=columns)
                    print(df.to_string(index=False))
                
                results_processed = True
        
        if not results_processed:
            print(f"No data found for month {month}")
            return False
        return True
        
    except mysql.connector.Error as e:
        print(f"Database Error: {e}")
        return False
    except Exception as e:
        print(f"Error generating supplier report: {e}")
        return False
    
# 2-5 Shaoxiang Qu
def view_supplier_products_detail(cursor):
    supplier_id = input("Enter Supplier ID or press Enter for all: ").strip()
    if supplier_id:
        cursor.execute("select * from supplier_products_detail_view where supplier_id = %s order by supplier_name, product_name", (int(supplier_id),))
    else:
        cursor.execute("select * from supplier_products_detail_view order by supplier_name, product_name")
    prints()
    return None

# 2-6 Qixuan Yuan
def high_value_products_with_poor_selling():
    cursor.execute("select * from warehouse_management.high_value_products_with_poor_selling;")
    prints()

# 2-7 Qixuan Yuan
def misleading_suppliers():
    cursor.execute("select * from warehouse_management.misleading_suppliers;")
    prints()

# 3-1 Qixuan Yuan
def query_inventory(cursor, warehouseid=None, productid=None):
    s=""
    if warehouseid and productid:
        s="where warehouse_id={} and product_id={}".format(warehouseid,productid)
    elif warehouseid:
        s="where warehouse_id={}".format(warehouseid)
    elif productid:
        s="where product_id={}".format(productid)
    cursor.execute("select * from inventory {} order by inventory_id".format(s))
    prints()
    return None

# 3-2 Qixuan Yuan
def split_inventory(sourceid,qty,operatorid,toware,newlocation):
    cursor.execute("call split_inventory({},{},{},{},\"{}\")".format(int(sourceid),int(qty),int(operatorid),int(toware),newlocation))
    print("Split success. Below are inventory changes.")
    cursor.execute("select * from inventory where inventory_id={} or inventory_id=(select max(inventory_id) from inventory)".format(sourceid))
    prints()
    print("Below are inventory_adjustment log.")
    if toware==-1:
        cursor.execute("select * from inventory_adjustments where adjustment_id=(select max(adjustment_id) from inventory_adjustments)")
    else:
        cursor.execute("select * from inventory_adjustments where adjustment_id=(select max(adjustment_id) from inventory_adjustments) or adjustment_id=(select max(adjustment_id) from inventory_adjustments)-1")
    prints()

# 3-3 Qixuan Yuan
def expiring_items(cursor, days):
    cursor.execute("""
        select inventory_id, product_id, warehouse_id, expiry_date,
        datediff(expiry_date, CURDATE()) as days_to_expire, total_quantity
        from inventory
        where expiry_date is not null and expiry_date<=date_add(curdate(), interval {} day)
        order by expiry_date asc
    """.format(int(days)))
    prints()
    return None

# 4-1 Qixuan Yuan
def create_inbound_order(type,productid,warehouseid,expected,total_items,operator,notes=""):
    cursor.execute("call create_inbound_order(\"{}\",{},{},{},{},{},\"{}\")".format(type,int(productid),int(warehouseid),int(expected),int(total_items),int(operator),notes))
    print("Inbound order created. Below is the record.")
    cursor.execute("select * from inbound_orders where inbound_id=(select max(inbound_id) from inbound_orders)")
    prints()

# 4-2 Qixuan Yuan
def complete_inbound(inboundid,actualqty,newlocation):
    cursor.execute("call complete_inbound({},{},\"{}\")".format(int(inboundid),int(actualqty),newlocation))
    print("Inbound order completed. Below is the record.")
    cursor.execute("select * from inbound_orders where inbound_id={}".format(int(inboundid)))
    prints()
    print("Inventory changes.")
    cursor.execute("select * from inventory where inventory_id=(select max(inventory_id) from inventory)")
    prints()

# 4-3 Shaoxiang Qu
def view_inbound_delay_warnings(cursor):
    try:
        cursor.execute("""
            select ida.alert_id, ida.inbound_id, ida.reference_number, w.warehouse_name, p.product_name, ida.delay_days, ida.alert_level, ida.alert_message, ida.created_at
            from inbound_delay_alerts ida
            left join warehouses w on w.warehouse_id = ida.warehouse_id
            left join products p on p.product_id = ida.product_id
            order by ida.delay_days desc, ida.created_at desc
        """)
        
        rows = cursor.fetchall()
        if rows:
            df = pd.DataFrame(rows, columns = ['alert_id', 'inbound_id', 'reference', 'warehouse', 'product','delay_days', 'alert_level', 'message', 'created_at'])
            
            print(f"\nAll inbound delay alerts")
            print(df.to_string(index = False))
            critical_count = len(df[df['alert_level'] == 'critical'])
            warning_count = len(df[df['alert_level'] == 'warning'])
            total_count = len(df)
            print(f"\nAlert summary")
            print(f"Total alerts: {total_count}")
            print(f"Critical alerts: {critical_count}")
            print(f"Warning alerts: {warning_count}")
            
            if not df.empty:
                max_delay = df['delay_days'].max()
                worst_alert = df[df['delay_days'] == max_delay].iloc[0]
                print(f"\nMost critical alert")
                print(f"Reference: {worst_alert['reference']}")
                print(f"Warehouse: {worst_alert['warehouse']}")
                print(f"Product: {worst_alert['product']}")
                print(f"Delay: {worst_alert['delay_days']} days")
                print(f"Level: {worst_alert['alert_level']}")
                print(f"Message: {worst_alert['message']}")
            
            return True
        else:
            print("No inbound delay alerts found.")
            return False
            
    except Exception as e:
        print(f"Error retrieving inbound delay alerts: {e}")
        return False

# 5-1 Qixuan Yuan
def create_outbound_order(type,productid,warehouseid,total_items,total_qty,picker,packer):
    cursor.execute("call create_outbound_order(\"{}\",{},{},{},{},{},{})".format(type,int(productid),int(warehouseid),int(total_items),int(total_qty),int(picker),int(packer)))
    print("Outbound order created. Below is the record.")
    cursor.execute("select * from outbound_orders where outbound_id=(select max(outbound_id) from outbound_orders)")
    prints()

# 5-2 Qixuan Yuan
def complete_outbound(inventoryid,outboundid):
    cursor.execute("call complete_outbound({},{})".format(int(inventoryid),int(outboundid)))
    print("Outbound order completed. Below is the record.")
    cursor.execute("select * from outbound_orders where outbound_id={}".format(int(outboundid)))
    prints()
    print("Inventory changes.")
    cursor.execute("select * from inventory where inventory_id={}".format(int(inventoryid)))
    prints()

# 5-3 Shaoxiang Qu
def view_outbound_delay_warnings(cursor):
    try:
        cursor.execute("""
            select oda.alert_id, oda.outbound_id, oda.reference_number, w.warehouse_name, p.product_name, oda.delay_days, oda.alert_level, oda.alert_message, oda.created_at
            from outbound_delay_alerts oda
            left join warehouses w on w.warehouse_id = oda.warehouse_id
            left join products p on p.product_id = oda.product_id
            order by oda.delay_days desc, oda.created_at desc
        """)
        
        rows = cursor.fetchall()
        if rows:
            df = pd.DataFrame(rows, columns = ['alert_id', 'outbound_id', 'reference', 'warehouse', 'product','delay_days', 'alert_level', 'message', 'created_at'])

            print(f"\nAll outbound delay alerts")
            print(df.to_string(index = False))
            critical_count = len(df[df['alert_level'] == 'critical'])
            warning_count = len(df[df['alert_level'] == 'warning'])
            total_count = len(df)
            print(f"\nAlert summary")
            print(f"Total alerts: {total_count}")
            print(f"Critical alerts: {critical_count}")
            print(f"Warning alerts: {warning_count}")
            
            if not df.empty:
                max_delay = df['delay_days'].max()
                worst_alert = df[df['delay_days'] == max_delay].iloc[0]
                print(f"\nMost critical alert")
                print(f"Reference: {worst_alert['reference']}")
                print(f"Warehouse: {worst_alert['warehouse']}")
                print(f"Delay: {worst_alert['delay_days']} days")
                print(f"Lvel: {worst_alert['alert_level']}")
                print(f"Message: {worst_alert['message']}")

            return True
        else:
            print("No outbound delay alerts found.")
            return False
            
    except Exception as e:
        print(f"Error retrieving delay alerts: {e}")
        return False

# 6-1 Shaoxiang Qu
def view_employee_details(cursor):
    emp_id = input("Enter Employee ID or press Enter for all: ").strip()
    if emp_id:
        cursor.execute("select * from employee_details_view where employee_id = %s", (int(emp_id),))
    else:
        cursor.execute("select * from employee_details_view")
    prints()
    return None

# 6-2 Shaoxiang Qu
def view_department_employee_stats(cursor):
    cursor.execute("select * from department_employee_stats_view order by total_employees desc")
    prints()
    return None

# 6-3 Shaoxiang Qu
def view_warehouse_employee_distribution(cursor):
    wh_id = input("Enter Warehouse ID or press Enter for all: ").strip()
    if wh_id:
        cursor.execute("select * from warehouse_employee_distribution_view where warehouse_id = %s order by total_employees desc", (int(wh_id),))
    else:
        cursor.execute("select * from warehouse_employee_distribution_view order by total_employees desc")
    prints()
    return None

# 6-4 Shaoxiang Qu
def view_employee_operation_stats(cursor):
    emp_id = input("Enter Employee ID or press Enter for all: ").strip()
    if emp_id:
        cursor.execute("select * from employee_operation_stats_view where employee_id = %s order by (total_inbound_operations + total_outbound_operations) desc", (int(emp_id),))
    else:
        cursor.execute("select * from employee_operation_stats_view order by (total_inbound_operations + total_outbound_operations) desc")
    prints()
    return None

# 6-5 Shaoxiang Qu
def check_employee_in_warehouse(cursor):
    emp_id = input("Enter employee ID: ").strip()
    wh_id = input("Enter warehouse ID: ").strip()
    cursor.execute("select is_employee_in_warehouse(%s, %s) as is_in_warehouse", (int(emp_id), int(wh_id)))
    result = cursor.fetchone()
    if result is not None:
        is_in_warehouse = result[0]
        print(f"Employee {emp_id} is {'in' if is_in_warehouse else 'not in'} warehouse {wh_id}")
    else:
        print("Unable to determine employee location")
    return None

# 6-6 Shaoxiang Qu
def get_department_employee_count_func(cursor):
    cursor.execute("select department, active_employees from department_employee_stats_view order by active_employees desc") 
    results = cursor.fetchall()
    print("Department Employee Counts (Active Employees Only):")
    print("-" * 40)
    total_count = 0
    for row in results:
        dept = row[0]
        count = row[1]
        total_count += count
        dept_display = dept.replace('_', ' ').title()
        print(f"{dept_display:20} : {count:3} active employees")
    
    print("-" * 40)
    print(f"{'TOTAL':20} : {total_count:3} active employees")
    return None

# 6-7 Shaoxiang Qu
def update_employee_status_proc(cursor):
    emp_id = input("Enter employee ID: ").strip()
    print("Available statuses:")
    print("1. active")
    print("2. terminated")
    print("3. leave")
    
    choice = input("Enter status number (1-3): ").strip()
    status_map = {
        '1': 'active',
        '2': 'terminated',
        '3': 'leave'
    }
    
    if choice in status_map:
        result_args = cursor.callproc('update_employee_status', [int(emp_id), status_map[choice], ''])
        print(result_args[2])
    else:
        print("Invalid status choice")
    return None

# 7-1 Qixuan Yuan
def inventory_value_by_product(cursor):
    cursor.execute("select * from inventory_value_by_product")
    prints()
    return None

# 7-2 Shaoxiang Qu
def category_inventory_overview(cursor, category_name=None):
    sql = """
    select p.category, count(distinct p.product_id) as sku_count, count(distinct i.inventory_id) as inventory_locations, ifnull(sum(i.total_quantity), 0) as total_quantity, ifnull(sum(i.locked_quantity), 0) as locked_quantity, ifnull(sum(i.available_quantity), 0) as available_quantity, ifnull(sum(i.total_quantity * p.value), 0) as inventory_value,
        case 
            when count(distinct p.product_id) = 0 then 0
            else ifnull(sum(i.total_quantity * p.value), 0) / count(distinct p.product_id)
        end as avg_value_per_sku,
        case 
            when ifnull(sum(i.total_quantity), 0) = 0 then 0
            else ifnull(sum(i.locked_quantity), 0) / ifnull(sum(i.total_quantity), 0) * 100
        end as lock_percentage
    from products p
    left join inventory i on i.product_id = p.product_id
    {}
    group by p.category
    order by inventory_value desc
    """.format("where p.category = %s" if category_name else "")
    
    if category_name:
        cursor.execute(sql, (category_name,))
    else:
        cursor.execute(sql)
    prints()
    return None

# Update to active delay triggers - Shaoxiang Qu
def trigger_delay_alerts(cursor):
    try:    
        cursor.execute("""
            update inbound_orders 
            set status = status
            where status in ('pending', 'receiving') 
            and datediff(now(), created_time) > 5
        """)
        inbound_updated = cursor.rowcount

        cursor.execute("""
            update outbound_orders 
            set status = status  
            where status in ('pending', 'picking', 'packing') 
            and datediff(now(), created_time) > 3
        """)
        outbound_updated = cursor.rowcount
        
        print("Delay alerts triggered.")
        
        return True
        
    except Exception as e:
        print(f"Error triggering alerts: {e}")
        return False

# Main loop
while True:
    printopt()
    opt=input("Enter option:").strip()

    if opt=="8":
        break

    elif opt=="1-1":
        list_warehouses(cursor)

    elif opt=="1-2":
        get_warehouse_utilization(cursor)

    elif opt=="1-3":
        wid=input("warehouse_id (Enter=all):").strip()
        warehouse_inventory_overview(cursor,wid if wid else None)

    elif opt=="1-4":
        high_writeoff_rate_warehouses()

    elif opt=="1-5":
        calculate_utilization()

    elif opt=="2-1":
        list_products(cursor)

    elif opt=="2-2":
        pid=input("product_id:").strip()
        get_product_suppliers(cursor,pid)

    elif opt=="2-3":
        pid=input("product_id:").strip()
        calculate_sell_through_rate(cursor,pid)

    elif opt=="2-4":
        month=input("month(YYYY-MM):").strip()
        generate_supplier_monthly_report(cursor,month)

    elif opt=="2-5":
        view_supplier_products_detail(cursor)

    elif opt=="2-6":
        high_value_products_with_poor_selling()

    elif opt=="2-7":
        misleading_suppliers()

    elif opt=="3-1":
        wid=input("warehouse_id(-1=all):").strip()
        pid=input("product_id(-1=all):").strip()
        wid=None if wid=="-1" else wid
        pid=None if pid=="-1" else pid
        query_inventory(cursor,wid,pid)

    elif opt=="3-2":
        print("e.g input:1 20 1 1 Z-01-11")
        sourceid=input("source_inventory_id:").strip()
        qty=input("split_qty:").strip()
        operator=input("operator_id:").strip()
        towh=input("to_warehouse:").strip()
        newloc=input("new_location:").strip()
        split_inventory(sourceid,qty,operator,towh,newloc)

    elif opt=="3-3":
        days=input("days_window:").strip()
        expiring_items(cursor,days)

    elif opt=="4-1":
        print("e.g input:purchase,5,2,130,1,2,test")
        print("For trigger on operater: purchase,5,2,130,1,3,test")
        print("For trigger on location utilization:first enter the same input as the normal one, and when complete the inbound,enter the actual quantity 1000000")
        t=input("inbound_type(return,purchase,transfer):").strip()
        pid=input("product_id:").strip()
        wid=input("warehouse_id:").strip()
        exp=input("expected_qty:").strip()
        total=input("total_items:").strip()
        op=input("operator_id:").strip()
        notes=input("notes(Enter=None):").strip()
        notes=None if notes=="" else notes
        create_inbound_order(t,pid,wid,exp,total,op,notes)

    elif opt=="4-2":
        print("e.g input:301,120,Z-01-09")
        inboundid=input("inbound_id:").strip()
        actual=input("actual_qty:").strip()
        batch=input("new_location:").strip()
        complete_inbound(inboundid,actual,batch)

    elif opt=="4-3":
        trigger_delay_alerts(cursor)
        view_inbound_delay_warnings(cursor)

    elif opt=="5-1":
        print("e.g input:sales,76,3,1,10,3,8")
        t=input("outbound_type(sales,transfer,return):").strip()
        pid=input("product_id:").strip()
        wid=input("warehouse_id:").strip()
        total_items=input("total_items:").strip()
        total_qty=input("total_qty:").strip()
        picker=input("picker_id:").strip()
        packer=input("packer_id:").strip()
        packer=None if packer=="" else packer
        create_outbound_order(t,pid,wid,total_items,total_qty,picker,packer)

    elif opt=="5-2":
        print("e.g input:1 251")
        inv_id=input("inventory_id:").strip()
        out_id=input("outbound_id:").strip()
        complete_outbound(inv_id,out_id)

    elif opt=="5-3":
        trigger_delay_alerts(cursor)
        view_outbound_delay_warnings(cursor)

    elif opt=="6-1":
        view_employee_details(cursor)

    elif opt=="6-2":
        view_department_employee_stats(cursor)

    elif opt=="6-3":
        view_warehouse_employee_distribution(cursor)

    elif opt=="6-4":
        view_employee_operation_stats(cursor)

    elif opt=="6-5":
        check_employee_in_warehouse(cursor)

    elif opt=="6-6":
        get_department_employee_count_func(cursor)

    elif opt=="6-7":
        update_employee_status_proc(cursor)

    elif opt=="7-1":
        inventory_value_by_product(cursor)

    elif opt=="7-2":
        category=input("category(Enter=all):").strip()
        category_inventory_overview(cursor,category if category else None)

    else:
        print("Invalid Input")

    press_enter()

print("Thank you!")
cursor.close()
db_conn.close()
