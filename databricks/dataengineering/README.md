# databricks/dataengineering/

## Summary

Notes from https://udemy.com/course/databricks-certified-data-engineer-professional.
Repo: https://github.com/derar-alhussein/Databricks-Certified-Data-Engineer-Professional

## Scenario

- Book store dataset. There are 3 tables, customers, orders, and books. We'll build a medallion (multi-hop) architecture across bronze, silver, and gold layers. Overall flow:
  - Kafka to 'multiplex' bronze table(s),
  - Refining `orders` in silver layer to look at quality enforement, streaming deduplication, scd type 2, and batch overwrite logic.
  - use CDC to create silver `customers` table, 
  - look at CDF to propogate incremental changes to downstream tables
  - streaming joins (stream-to-stream, stream-to-static)
  - store views and materialized views in gold.

# Ingestion and Data Processing

- When ingesting to bronze, need to decide how input datasets should be mapped: 1:1 i.e. singleplex, or *:1 i.e. multiplex
- Singleplex is traditional ingestion model, where each data source or topic is ingested into a separate table. Works well for batch processing. However, for streaming processes of large datasets, having 1 streaming job per table will hit the max concurrent job limit (1000 jobs per workspace) much faster. So, can use multiplex ingestion model to stream many topics into a single bronze table. 
- Can source from pub/sub or kafka, or files/cloud object storage using autoloader.
- Extending the book store example, you would have a single table with a key column for topic, and a value column with the record in e.g. json format.
- Later in the pipeline, silver layer tables would be created from this single bronze table. 

## Multiplexed bronze table ingestion

- Simulating a kafka stream with files in storage which contain the data
- To read, we are defining a function which includes a `spark.readStream` and `writeStream` component. 
- For the read:
  - `.format("cloudFiles")` configures Autoloader
  - `.option("cloudFiles.format", "json")` specifies the inbound format
  - schema is passed in with `.schema(schema)` (which is set earlier in the code)
  - `.load` is included to pass the folder path with the 'arriving' files
  - then some `.withColumn` lines to parse the timestamp and have a `year_month` column too.
- For the write:
  - we pass a `.option("checkpointLocation", "$PATH")` (he uses dbfs here)
  - `.option("mergeSchema", True)` to atomatically evolve the schema when new fields are detected
  - `.partitionBy("topic", "year_month")` (probably unnecessary!)
  - `.trigger(availableNow=True)` to execute the query in batch mode
  - `.table("bronze)` to write to the bronze table
- Check the data landed by loading to a df with `spark.table("bronze")` - can also query this with SQL using SQL magic

- `CAST(value as STRING)` to cast binary columns as strings
- Parse using `from_json()`, passing the schema details
- Convert static table to a streaming temporary view with `spark.readStream.table("bronze").createOrReplaceTempView("bronze_tmp")` to enable us to write streaming queries with spark SQL - operate on the temp view by running transformation query against `bronze_tmp`. 
- Make the transformed data available to python from SQL by running `CREATE OR REPLACE TEMPORARY VIEW orders_silver_temp AS $transformation`. The temp view is used as an intermediary to capture the query we want to apply.
- Persist the transformed data with a streaming write - `spark.table("orders_silver_tmp").writeStream.option("checkpointLocation", "dbfs:/[...]").trigger(availableNow=True).table("orders_silver")`. 
  - `trigger(availableNow=True)` processes multiple microbatches until no more data is available, then stops.
- whole pipeline here can be expressed with pyspark dataframe API too.
  - `.filter()` to retrieve records for a specific topic
  - `.from_json()` available in pyspark too

When using Auto Loader, several options can be configured for your stream to ensure reliable data ingestion:

### Setting Maximum Bytes per Trigger

If you're ingesting large files that cause long micro-batch processing times or memory issues, you can use the `cloudFiles.maxBytesPerTrigger` option to control the maximum amount of data processed in each micro-batch. This improves stability and keeps batch durations more predictable. For example, to limit each micro-batch to 1 GB of data, you can configure your stream as follows:

```
spark.readStream
    .format("cloudFiles")
    .option("cloudFiles.format", <source_format>)
    .option("cloudFiles.maxBytesPerTrigger", "1g")
    .load("/path/to/files")
```

### Handling Bad Records

When working with JSON or CSV files, you can use the `badRecordsPath` option to capture and isolate invalid records in a separate location for further review. Records with malformed syntax (e.g., missing brackets, extra commas) or schema mismatches (e.g., data type errors, missing fields) are redirected to the specified path.

```
spark.readStream
     .format("cloudFiles")
     .option("cloudFiles.format", "json")
     .option("badRecordsPath", "/path/to/quarantine")
     .schema("id int, value double")
     .load("/path/to/files")
```

### Files Filters

To filter input files based on a specific pattern, such as *.png, you can use the `pathGlobFilter` option. For example:

```
spark.readStream
     .format("cloudFiles")
     .option("cloudFiles.format", "binaryFile")
     .option("pathGlobfilter", "*.png")
     .load("/path/to/files")
```

### Schema Evolution

Auto Loader detects the addition of new columns in input files during processing. To control how this schema change is handled, you can set `cloudFiles.schemaEvolutionMode` option:

```
spark.readStream
     .format("cloudFiles")
     .option("cloudFiles.format", <source_format>)
     .option("cloudFiles.schemaEvolutionMode", <mode>)
     .load("/path/to/files")
```

The supported schema evolution modes include: `addNewColumns`, `rescue`, `failOnNewColumns`, and `none`. More: https://docs.databricks.com/aws/en/ingestion/cloud-object-storage/auto-loader/schema#how-does-auto-loader-schema-evolution-work

The default mode is `addNewColumns`, so when Auto Loader detects a new column, the stream stops with an `UnknownFieldException`. Before your stream throws this error, Auto Loader updates the schema location with the latest schema by merging new columns to the end of the schema. The next run of the stream executes successfully with the updated schema.

Note that the `addNewColumns` mode is the default when a schema is not provided, but `none` is the default when you provide a schema. `addNewColumns` is not allowed when the schema of the stream is provided.

## Quality Enforcement

- We'll add quality checks using `CHECK` constraints, which apply boolean filters to columns and prevent data which violates the constraint being written.
- Constraints can be defined on existing tables using [`ALTER TABLE $TABLE ADD CONSTRAINT`](https://learn.microsoft.com/en-us/azure/databricks/sql/language-manual/sql-ref-syntax-ddl-alter-table-add-constraint). PK and FK constraints are informational. `CHECK` constraints are enforced - condition must be a deterministic expression returning a BOOLEAN. Looks like a standard `WHERE` clause.
- See constraints `DESCRIBE EXTENDED $TABLE`
- If you try to add a `CHECK` constraint to a table with rows already in it that violate the constraint, the `ALTER` statement will fail.
  - To handle this, we could manually delete bad records, or set the check constraint before inserting data... but the writes would still fail. 
  - We can filter these records before writing by adding an additional `.filter("quantity > 0")` to our `spark.readStream` i.e. _fix the issue upstream_.
- Constraints can be removed using `DROP CONSTRAINT`

## Streaming De-duplication

- Sourcing data from Kafka can introduce duplicate records because of delivery guarantees. We'll implement de-duplication in the silver layer, as the bronze should maintain a history of the true state of our streaming source.
- This prevents potential data loss from aggressive quality enforcement/pre-processing at the initial ingestion stage.
- Check number of orders with `spark.read.table("bronze").filter("topic = 'orders'").count()`
- With static data, we can use `.dropDuplicates(["order_id", "order_timestamp"])`, passing in the columns to identify unique records. 
- `dropDuplicates` can also be used with spark structured streaming, which can track state information for the unique keys in the data and ensure dupes do not exist between or within microbatches. Over time, this state info will grow to repesent all history - the amount of state to be maintained can be managed using Watermarking.
- Watermarking allows us to only track state information for a window of time in which we expect records could be delayed. Watermark is set on the `readStream` with `.withWatermark("order_timestamp", "30 seconds")`:
    ```
    deduped_df = (spark.readStream
                    .table("bronze")
                    .filter("topic = 'orders'")
                    .select(F.from_json(F.col("value").cast("string"), json_schema).alias("v"))
                    .select("v.*")
                    .withWatermark("order_timestamp", "30 seconds")
                    .dropDuplicates(["order_id", "order_timestamp"]))
    ```
- As each microbatch is processed, also need to ensure that records to be inserted are not already in the target table - this can be managed using insert-only merge:
    ```
    def upsert_data(microBatchDF, batch):
        microBatchDF.createOrReplaceTempView("orders_microbatch") # <- store the records to be inserted in a temp view
        
        sql_query = """
        MERGE INTO orders_silver a
        USING orders_microbatch b
        ON a.order_id=b.order_id AND a.order_timestamp=b.order_timestamp # <- Logic to match on unique keys
        WHEN NOT MATCHED THEN INSERT * # <- Insert when keys do not exist in the target table
        """
        
        microBatchDF.sparkSession.sql(sql_query) # <- execute the query using the local spark session from the microbatch df
        #microBatchDF._jdf.sparkSession().sql(sql_query) <- syntax slightly different in DBR 10.5 and earlier
    ```
- Defined as a function which is called during the processing of each microbatch
- To use the function in the stream, use `forEachBatch` method, passing the function in i.e. `forEachBatch(upsert_data)`, where we can pass our custom writing logic for each microbatch of streaming data
    ```
    query = (deduped_df.writeStream
                   .foreachBatch(upsert_data)
                   .option("checkpointLocation", f"{bookstore.checkpoint_path}/orders_silver")
                   .trigger(availableNow=True)
                   .start())

    query.awaitTermination()
    ```

## Slowly Changing Dimensions

- SCD - data management concept to determine how tables handle data over time
- Type 0 - no change allowed - static or append only
- Type 1 - full refresh - no history retained (Delta Time Travel can be used if needed)
- Type 2 - new row for each change and mark old obsolete - retains full history over time
- NB: Time travel is _not_ a long term versioning solution - cost and performance gets worse over time, and `VACCUM` will cause the historical versions to be deleted.

### SCD Type 2

- Idea here is to track book prices over time, to verify order totals at any given time
- First, the merge statement to call in the `foreachBatch` call:
    ```
    def type2_upsert(microBatchDF, batch):
        microBatchDF.createOrReplaceTempView("updates") # <- create the temp view for each microbatch 
        
        sql_query = """
            MERGE INTO books_silver
            USING (
                SELECT updates.book_id as merge_key, updates.* # <- retrieve inbound updates from the temp view, with merge_key
                FROM updates

                UNION ALL

                SELECT NULL as merge_key, updates.*
                FROM updates # <- reprocessing with NULL merge key to insert updates with NOT MATCHED clause
                JOIN books_silver ON updates.book_id = books_silver.book_id
                WHERE books_silver.current = true AND updates.price <> books_silver.price # <- get instances of inbound books data where they already exist in the books_silver table, is the current record, and the price is different 
            ) staged_updates
            ON books_silver.book_id = merge_key 
            WHEN MATCHED AND books_silver.current = true AND books_silver.price <> staged_updates.price THEN
            UPDATE SET current = false, end_date = staged_updates.updated # <- when matched, then update to reflect no longer current, with end date, and...
            WHEN NOT MATCHED THEN
            INSERT (book_id, title, author, price, current, effective_date, end_date) # <- insert inbound data as new record
            VALUES (staged_updates.book_id, staged_updates.title, staged_updates.author, staged_updates.price, true, staged_updates.updated, NULL)
        """
        
        microBatchDF.sparkSession.sql(sql_query)
    ```
- Call the function in the `foreachBatch`:
    ```
    def process_books():
    schema = "book_id STRING, title STRING, author STRING, price DOUBLE, updated TIMESTAMP"
 
    query = (spark.readStream
                    .table("bronze")
                    .filter("topic = 'books'")
                    .select(F.from_json(F.col("value").cast("string"), schema).alias("v"))
                    .select("v.*")
                 .writeStream
                    .foreachBatch(type2_upsert)
                    .option("checkpointLocation", f"{bookstore.checkpoint_path}/books_silver")
                    .trigger(availableNow=True)
                    .start()
            )
    
    query.awaitTermination()
    
    process_books()
    ```
- He creates a `current_books` table, with `CREATE OR REPLACE TABLE` from books_silver with clause `WHERE current IS TRUE`

## Change Data Capture (CDC)

- CDC is about identifying change in the source and delivering those changes to the target system. 
- Changes could be row level changes (INSERT/UPDATE/DELETE)
- The changes are logged at the source as events that contain the record as well as metadata, like the change type, and a version number or timestamp to indicate the sequence of events or time that a change occurred. 
- CDC feed can be processed in delta lake using `MERGE INTO`, which allows a set of INSERT/UPDATE/DELETE commands to be processed in delta. 
    ```
    MERGE INTO target_table t
    USING source_updates s
    ON t.key_field = s.key_field
    WHEN MATCHED AND t.sequence_field < s.sequence_field
        THEN UPDATE SET *
    WHEN MATCHED AND s.operation_field = "DELETE"
        THEN DELETE 
    WHEN NOT MATCHED
        THEN INSERT *
    ```
- MERGE cannot be performed if multiple source rows match and attempt to modify the same row in the delta table - so if there could be multiple updates for the same key, this will generate an exception - so ensure only the most recent changes are being merged!
- This can be done with the `rank()` function: `rank().over(Window)`. A window is a group of records with the same partition key sorted by an ordering column in descending order. The most recent records would have rank = 1.

### Rank types

- Dense Rank - If two rows are tied for 1st place, the next rank assigned will be 2nd (i.e., 1, 1, 2).
- Rank - If two rows are tied for 1st place, the next rank assigned will be 3rd (i.e., 1, 1, 3).
- Percent Rank - calculates the relative rank of a row within a partition as a percentage

### Processing `customer` records using 'CDC'

- First, get the customer records from our bronze table:
    ```
    from pyspark.sql import functions as F

    schema = "customer STRING, email STRING, first_name STRING, last_name STRING, gender STRING, city STRING, country_code STRING, row_status STRING, row_time timestamp"

    customers_df = (spark.table("bronze")
                        .filter("topic = 'customers'")
                        .select(F.from_json(F.col(value).cast("string"), schema).alias("v"))
                        .select("v.*")
                        .filter(F.col("row_status").isin(["insert", "update"])))
    
    display(customers_df)
    ```
- Focus on insert and update records for now - will processes deletes later..
- Get the most recent changes using the Window function, drop the other records and the rank column:
    ```
    from pyspark.sql.window import Window

    window = Window.partitionBy("customer_id).orderBy(F.col("row_time").desc())

    ranked_df = (customers_df.withColumn("rank", F.rank().over(window))
                                .filter("rank == 1")
                                .drop("rank"))
    
    display(ranked_df)
    ```
- Can't apply this window (i.e. non-time based window function) to `readStream` - it's not supported. I guess you need to bound the stream somehow..? He uses the similar microbatch logic like we saw in [SCD Type 2](#scd-type-2) section, but I'm not sure this would work for late arriving data.
  - Late arriving data is handled in the `MERGE` sql: `WHEN MATCHED AND c.processed_timestamp < r.processed_timestamp THEN UPDATE SET *` - we ensure the `processed_timestamp` in the new data is newer than the current data.

    ```
    def batch_upsert(microBatchDF, batchId):
        window = Window.partitionBy("order_id", "customer_id").orderBy(F.col("_commit_timestamp").desc())
        
        (microBatchDF.filter(F.col("_change_type").isin(["insert", "update_postimage"]))
                    .withColumn("rank", F.rank().over(window))
                    .filter("rank = 1")
                    .drop("rank", "_change_type", "_commit_version")
                    .withColumnRenamed("_commit_timestamp", "processed_timestamp")
                    .createOrReplaceTempView("ranked_updates"))
        
        query = """
            MERGE INTO customers_orders c
            USING ranked_updates r
            ON c.order_id=r.order_id AND c.customer_id=r.customer_id
                WHEN MATCHED AND c.processed_timestamp < r.processed_timestamp
                THEN UPDATE SET *
                WHEN NOT MATCHED
                THEN INSERT *
        """
    
    microBatchDF.sparkSession.sql(query)
    ```
    
    ```
    def batch_upsert(microBatchDF, batchId):
        window = Window.partitionBy("customer_id").orderBy(F.col("row_time").desc())
        
        (microBatchDF.filter(F.col("row_status").isin(["insert", "update"]))
                    .withColumn("rank", F.rank().over(window))
                    .filter("rank == 1")
                    .drop("rank")
                    .createOrReplaceTempView("ranked_updates"))
        
        query = """
            MERGE INTO customers_silver c
            USING ranked_updates r
            ON c.customer_id=r.customer_id
                WHEN MATCHED AND c.row_time < r.row_time
                THEN UPDATE SET *
                WHEN NOT MATCHED
                THEN INSERT *
        """
    
    microBatchDF.sparkSession.sql(query)
    ```

- He builds on this to extend the `readStream` to join in some static reference data - lookup of `country_name` from `country_code`: `.join(F.broadcast(df_country_lookup), F.col("country_code") == F.col("code"), "inner")`. Broadcast join for small lookup table (like a replicated table, the reference data will be instanciated on each node in the cluster). Mark which `df` is small enough for broadcasting with the `broadcast()` function.

## Change Data Feed (CDF)

- CDF is a new feature built into Delta Lake to autoatically create CDC feeds about delta lake tables. It is **not** enabled by default. CDF records row-level changes for all data written to a delta table. 
- Enables changes to be propoaged to downstream changes in multi-hop "architecture".
- Changes are recorded in the `table_changes` - this includes the row data along with the change type, timestamp of the change, and the delta table version number which contains the change.
- `UPDATE`d records always have 2 records present - `update_preimage` and `update_postimage`, which can be used to evaluate the change(s) that were made.
- Changes can be queried using `SELECT * FROM table_changes('table_name', start_version, [end_version])`. Can also query on `start_timestamp` and `end_timestamp` for the start and end limits. 
- Enable it by using `TBLPROPERTIES (delta.enableChangeDataFeed = true)`. Can include in `CREATE` or `ALTER` table syntax.
- Additionally, set the `spark.databricks.delta.properties.default.enableChangeDataFeed` to true in spark config settings to enable on all newly created tables within the spark session.
- CDF follows the same retention policy as the table. So, if `VACUUM` is run on the table, the CDF data is also deleted.
- Generally:
  - using CDF for changes where UPDATEs and DELETEs are inclued. If append only, then no need as changes can be directly streamed from the table.
  - additionally, only use where a small fraction of changes are made during the processing of new data. If most records are updated or the table is completely overwritten, this will add significant overhead.
- When enabled, there will be a new `_change_data` directory in the delta table folder. The dir contains parquet files where the changes are recorded.

## Streaming joins

### Stream-to-stream

- He jumps straight to the code here - again, using the same microbatch approach as before.
- Defines a `batch_upsert` function, this time though, as joining the `customer` and `order` tables, he set the window as `window = Window.partitionBy("order_id", "customer_id").orderBy(F.col("_commit_timestamp").desc())` (ordering by the `_commit_timestamp` which we get from the CDF table)
- Still `.filter(F.col("_change_type").isin(["insert", "update_postimage"])` i.e. no deletes for the time being..
- These updates are then merged into the `customer_orders` table with the `MERGE` query:
    ```
    query = """
        MERGE INTO customers_orders c
        USING ranked_updates r
        ON c.order_id=r.order_id AND c.customer_id=r.customer_id
            WHEN MATCHED AND c.processed_timestamp < r.processed_timestamp
              THEN UPDATE SET *
            WHEN NOT MATCHED
              THEN INSERT *
    """
    ```
- To run the join between the two streaming tables, write the function:
    ```
    def process_customers_orders():
        orders_df = spark.readStream.table("orders_silver") # <- read the orders as a stream
    
        cdf_customers_df = (spark.readStream
                                .option("readChangeData", True)
                                .option("startingVersion", 2)
                                .table("customers_silver")
                        ) # <- take the customer updates from the change data for the customers_silver table  

        query = (orders_df
                    .join(cdf_customers_df, ["customer_id"], "inner")
                    .writeStream
                        .foreachBatch(batch_upsert)
                        .option("checkpointLocation", f"{bookstore.checkpoint_path}/customers_orders")
                        .trigger(availableNow=True)
                        .start()
                )
        
        query.awaitTermination()
    ```
- With this config, Spark will buffer past input as streaming state for both input streams, to ensure every future record can be joined with the data from each stream. 

### Stream-to-static

- Streaming tables are append only sources, but static tables can contain data which is updated, deleted, or overwritten. This means these tables cannot be streamed, because this breaks the append-only requirement of streaming tables.
- When joining to a static table, only newly arriving data on the streaming data will trigger re-processing. The latest version of the static data is returned each time it is queried. Adding new records to the static table will _not_ trigger re-processing or updates to the result of the stream-static join. _Only matched records at the time the stream is processed will be presented in the resulting table_. 
- Can we buffer the unmatched records as a streaming state to be matched later? _No_, as streaming joins are not stateful. To process these scenarios, a separate batch job would need to be configured to processes the missed data.
- [Example code here](https://github.com/derar-alhussein/Databricks-Certified-Data-Engineer-Professional/blob/main/3%20-%20Data%20Processing/3.4%20-%20Stream-Static%20Join.py)

### Trigger options

.trigger() options
  - processingTime will run a microbatch query for every period specified e.g. '1 minute'. Greater range of supported functionality (aggregations, joins, stateful ops). exactly once.
  - continuous will continuously run with low latency, and update checkpoint with progress for specified period. Reduced footprint of supported capability. limited set of stateless / narrow transformations . at least once semantics

## Materialized Views for Gold Tables

- Delta caching is used on subsequent queries to the same view in the same cluster which improves VIEW performance. But the result is not persisted and not available outside the current cluster.
- Materialized views in databricks 'most closely maps to the concept of a gold table', which help keep down the potential cost and latency associated with complex ad-hoc queries.

# Performance Optimization

## Partitioning

- Strategy for optimizing query performance on large delta tables. Partition = subset of rows that share the same value for a pre-defined subset of columns (i.e. partitioning columns). 
- Parition a table by including the `PARTITION BY ($col)` clause in the `CREATE TABLE` statement
- `OPTIMIZE` commands can be run at the parition level
- Partitions should be low cardinality and at least 1GB in size, or larger
- If records with a given value will continue to arrive indefinitely, `datetime` fields can be used for partitioning. 
    - Can also be useful to remove/archive older data.
- If data is deleted, and you still want to stream the data, use the `.option("ignoreDeletes", True)`, which enables stream processing from delta tables with parititon deletes.
- Deletion will not actually occur until `VACUUM` is run on the table. 

## Data file layout optimization

- Optimizing the layout of the data enables data skipping algorithms to skip data where appropriate to improve read performance.
- There are 3 things we can use, paritioning, z-order indexing, and liquid clustering
- **Partitioning** can improve performance for large delta tables as it physically separates the data into different files which, if used incorrectly, will create the many-small-files problem for spark to contend with. This also impacts what the `OPTIMIZE` command can do as it limits the compaction to partition level files which again leaves the small files problem.
  - Partitioning on high-cardinality columns is inifficient too, as creates large number of partitions
  - If you want to modify the partition columns, the full table will require a re-write.
- May instead consider **z-ordering**, which groups similar data into optimized files without creating directories. This is about co-locating and reorganizing column info in the same set of files by re-writing them in order. 
  - Impliment z order by including the `ZORDER BY` keyword in the `OPTIMIZE` command e.g. `OPTIMIZE table ZORDER BY column_name`
  - The main issue with `ZORDER` is it is not an incremental operation. When new data is ingested, the command must be run again to re-organize the data. 
- **LIQUID CLUSTERING** aims to solve this, by providing more flexibility and better performance. This is defined at the table level, which eliminates the need to specify them during each run of the OPTIMIZE command. 
  - Include by using the `CLUSTER BY` clause with the clustering columns. 
  - **Clustering is NOT compatible with the other techniques.** 
- Trigger the optimization by running `OPTIMIZE` after configuring the `CLUSTER BY` clause. Liquid clustering _is_ incremental, so another run after additional writes will only affect unoptimized files.  
- Choose the right cluster keys depending on your query patterns - use those that are frequently used in query filters. If you don't know this, **automatic liquid clustering** can be used to defer this decision to databricks, which will look at historical query workloads to select optimal cluster keys. This does require 'predictive optimization' on [UC managed tables](https://learn.microsoft.com/en-us/azure/databricks/delta/clustering#auto-liquid) - `EXTERNAL` tables are not supported. 
- Enable with `CLUSTER BY AUTO`

## Predictive Optimization 

- AI-driven feature that automatically handles maintenance operations for Unity Catalog **managed** tables, eliminating the need for manual tuning, improving query performance, and reducing storage costs.
- Predictive optimization runs the following operations automatically for enabled tables:
  - `OPTIMIZE` to triggers incremental clustering for enabled tables. If automatic liquid clustering is enabled, predictive optimization might select new clustering keys before clustering data (does not run ZORDER when executed with predictive optimization.)
  - `VACUUM` to reduces storage costs by deleting data files no longer referenced by the table.
  - `ANALYZE` to trigger incremental update of table statistics. These statistics are used by the query optimizer to generate an optimal query plan. See [ANALYZE TABLE](https://learn.microsoft.com/en-us/azure/databricks/sql/language-manual/sql-ref-syntax-aux-analyze-table).
- Predictive optimization is **enabled by default for new accounts**. To manually enable or disable predictive optimization for an account, navigate to Feature Enablement in your accounts console, or enable or disable predictive optimization for a catalog, or a schema using:
`ALTER CATALOG <catalog_name> { ENABLE | DISABLE } PREDICTIVE OPTIMIZATION;` / `ALTER SCHEMA <schema_name> { ENABLE | DISABLE } PREDICTIVE OPTIMIZATION;`
- Databricks recommends enabling predictive optimization for all Unity Catalog managed tables to simplify data maintenance and reduce storage costs.

## Delta Lake Transaction Log

- Resides in `_delta_log/` in a delta table sub-directory. Each commit to the table is written out as a `json` file
- Contains list of actions performed, e.g. adding/removing data files from the table. 
- In order to resolve the current state of the table, spark needs to process these files. This can be inefficient - databricks automatically creates `.checkpoint.parquet` files in this directory every 10 commits to accelerate resolution of the current table state. The files save the entire state of the table at a point im time in native parquet format. Easier than processing all the intermediate json files. 
- Additionally, delta lake includes statistics for the first 32 columns of the table each added data file in the transaction log, including number of records, min/max values, number of `null` values.
- Statistics will always be used by delta lake for file skipping - e.g. count of records is calculated by querying table statistics rather than the table data files itself. 
- NB: nested fields count towards the 'first 32 columns' limitation on column table statistics - i.e. 4 struct fields with 8 nested fields in each column will total the 32 columns.
- `VACCUM` does not delete the transaction log - just the data files. Databricks automatically cleans up the transaction log. Every time a checkpoint is written, databricks cleans up log entries older than the log retention interval (default 30 days). This limits time travel on a table by default to up to 30 days in the past. This can be configured with the `delta.logRetentionDuration` config on a table.

## Auto optimize

- Delta lake supports compacting small files by manually running the `OPTIMIZE` command. Typically, target file size is 1GB. Small files can be automatically compacted during individual writes to a table. Auto optimize consists of 2 complimentary features:
  - With **optimized writes** enabled, databricks will attempt to write out 128MB files for each partition. 
  - **Auto-compaction** will check after an individual write if files can be compacted further - if it can, it runs an `OPTIMIZE` job with 128MB file size instead of the standard 1GB in standard `OPTIMIZE`. 
    - Auto-compaction does not support ZORDER as ZORDER is significantly more expensive than compaction.
- These features can be enabled using `TBLPROPERTIES (delta.autoOptimize.optimizeWrite = true, delta.autoOptimize.autoCompact = true)`
- Many small files is not _always_ a problem as it can lead to better data skipping. 
- When executing frequent `MERGE` operations on a table, optimized writes and auto compaction will generate data files smaller than the default 128 MB which helps reduce duration of future `MERGE` operations.

## Deletion vectors

- Storage optimization feature you can enable on Delta Lake tables. 
- By default, when a single row in a data file is updated or deleted, the entire Parquet file containing the record must be rewritten. 
- With deletion vectors enabled for the table, `DELETE`, `UPDATE`, and `MERGE` operations create small files called "deletion vectors" to mark existing rows as removed or changed _without rewriting the Parquet file_. Subsequent reads on the table resolve the current table state by applying the deletions indicated by deletion vectors to the most recent table version.
- Deletion vectors indicate changes to rows as soft-deletes that logically modify existing Parquet data files in the Delta Lake table. These changes are applied physically when one of the following events causes the data files to be rewritten:
    - An `OPTIMIZE` command is run on the table.
    - Auto-compaction triggers a rewrite of a data file with a deletion vector.

### Enable deletion vectors

- Deletion vectors are enabled by default when you create a new table using a SQL warehouse or Databricks Runtime 14.1 or above.
- To manually enable or disable support for deletion vectors on any Delta table or view, use the `delta.enableDeletionVectors` table property.

## Python UDFs

- Custom column transformations can be implemented as UDFs
- Code a typical python function
- To use it on a pyspark dataframe, register it as a UDF `apply_discount_udf = udf(apply_discount)`, then call it:
    ```
    df_discounts = df_books.select("price", apply_discount_udf(col("price"), lit(50)))
    ```
- This UDF cannot be used in SQL - to register for use in SQL, use `apply_discount_py_udf = spark.udf.register("apply_discount_sql_udf", apply_discount)`, to register for use in Python and SQL - to call in py use the `apply_discount_py_udf`, and sql, `apply_discount_sql_udf`
- Can also define and register using `@udf()` decorator, where the parameter is the column data type the function returns e.g. `@udf("double")`
  - This approach prevents you from being able to locally call the python function
- Python UDF cannot be optimized by spark, and there is an additional cost of transferring data between spark engine and python interpreter.
- Pandas UDFs are vectorized UDFs that use Apache Arrow format (in memory that enables fast data transfers between sparks jvm and python runtime, to reduce computation and serialization costs)
    ```
    import pandas as pd
    from pyspark.sql.functions import pandas_udf

    def vectorized_udf(price: pd.Series, percentage: pd.Series,) -> pd.Series:
        return price * (1 - percentage/100)

    vectorized_udf = pandas_udf(vectorized_udf, "double")

    ### or ###

    @pandas_udf("double")
    def vectorized_udf(price: pd.Series, percentage: pd.Series,) -> pd.Series:
        return price * (1 - percentage/100)
    ```
- Register to SQL namespace `spark.udf.register("sql_vectorized_udf", vectorized_udf)`

### UDFs on groups

- In spark, you can apply custom Pandas-based operations on grouped data within a PySpark DataFrame. This allows you to perform group-level operations using familiar Pandas code while still benefiting from Spark’s distributed processing engine. To achieve this, use the `applyInPandas` function.
- Typically looks like this: `df.groupby("key").applyInPandas(custom_function, schema)`
- `custom_function` is a user-defined function (UDF) that accepts a Pandas DataFrame and returns another, while `schema` defines the structure of the output DataFrame. Spark handles the parallelization by splitting the data by groups and running the UDF across worker nodes. Each group is sent as a pandas DataFrame to the UDF, which preserves row order and allows running custom, stateful algorithms (e.g., rolling windows, and cumulative calculations), for example, We can use `applyInPandas` on our `customers_orders` table to calculate the average quantity of orders per country. Here’s an example in PySpark:
    ```
    import pandas as pd
    
    schema = "country STRING, avg_quantity DOUBLE"
    
    def avg_per_country(pdf):
        return pd.DataFrame({
            "country": [pdf["country"].iloc[0]],
            "avg_quantity": [pdf["quantity"].mean()]
        })
    
    df = spark.table("customers_orders")
    result = df.groupBy("country").applyInPandas(avg_per_country, schema)
    display(result)
    ```
- In practice, `applyInPandas` is widely used in data science workflows, particularly when analysts want to integrate Pandas’ rich ecosystem (such as NumPy, SciPy, or scikit-learn) into scalable Spark pipelines.

# Data Orchestration

## Lakeflow jobs

- He walks though a basic configuration of a databricks job, chaining notebook tasks and setting dependencies.
    - Going to orchestrate the end to end bookstore pipeline with databricks job, with a multi task job.
    - Add a task, reference a notebook, notebook params implemented with widgets can be added to the task in the Parameters section of the task
    - Can edit the job_cluster config, retries (can be unlimited!)
    - Job details has a `maximum concurrent runs` setting - set to 1 if you have unlimited retry policy
    - Remove display, adhoc SQL, unwanted file removal/table dropping etc from notebook tasks
    - Depends on field defaults to previously defined task
- Schedule can be added to the job with the Schedule section on the job overview - this uses a cron scheduling UI, can also put out in cron syntax
- Permissions section has 'owner', who's permission will be used to run the job. There is a separate 'run as' field at the top. If you change the owner (must be an individual i.e. not group), run as account is also updated. Creator does not change. 
  - Other users/groups can be granted 'Can view' to view, and/or run permissions on a job with 'Can Manage Run'

## Troubleshoot failure

- If a task fails, all dependent tasks will be skipped
- Can see the error by clicking on the task, which takes to the output
- Commands after failure are skipped too.
- Click on a failed run, use the 'Repair Run' to only re-run failed tasks. Gives you the tasks that will be re-run, and an option to pass in params.

# Data Privacy - Propogating deletes

- Set up a table called `delete_requests`, sink records here from `bronze` using `.filter("row_status = 'delete'")`
- Deletes can be processed in the same was as UPDATEs and INSERTs, but may have specific requirements around handling deletions (e.g. audit)
- He takes the `request_timestamp` and adds 30 days with `F.date_add("request_timestamp", 30).alias("deadline")` for the 'request deadline'. Also adds a `F.lit("requested").alias("status")` to track processing state.
- Propogate deletes from the CDF on the table
    ```
    def process_deletes(microBatchDF, batchId):
        (microBatchDF
            .filter("_change_type = 'delete'")
            .createOrReplaceTempView("deletes"))

        microBatchDF.sparkSession.sql("""
            DELETE FROM customers_orders
            WHERE customer_id IN (SELECT customer_id FROM deletes)
        """)
        
        microBatchDF.sparkSession.sql("""
            MERGE INTO delete_requests r
            USING deletes d
            ON d.customer_id = r.customer_id
            WHEN MATCHED
            THEN UPDATE SET status = "deleted"
        """)

    (deleteDF.writeStream
         .foreachBatch(process_deletes)
         .option("checkpointLocation", f"{bookstore.checkpoint_path}/deletes")
         .trigger(availableNow=True)
         .start())
    ```
- DELETE operation can be seen in the history.
- **Need to run VACUUM to _actually_ delete the data.**


# ETL Pipelines

## Lakeflow Declarative Pipelines

- LDP is a new ETL framework to define pipelines
- Based on spark, uses declarative approach. Define the desired outcome of the transformations, databricks handles execution details
- LDP was previously called Delta Live Tables - more recently open sources and integrated into Apache Spark ecosystem, renamed 'Spark Declarative Pipelines'
- LDP handles checkpointing, retries, performance optimization, and orchestration. Makes it easy to implement CDC, SCD type 2, DQ controls.
- Uses decorators to simplify - the decorator takes responsibility for writing the table, managing checkpoint etc
    ```
    # Spark
    (spark.readStream
            .format("cloudFiles")
            .option("cloudFiles.format", "json")
            .load("/some/path")
        .writeStream
            .option("checkpointLocation", "/path")
            .table("orders_raw")
    )

    # LDP
    from pyspark import pipelines as dp

    @dp.table
    def orders_raw():
        return (spark.readStream
                    .format("cloudFiles")
                    .option("cloudFiles.format", "json")
                    .load("/some/path")
                )
    ```
- Using spark, we cannot create streaming tables in spark sql syntax alone. Must run through pyspark to register streaming tables. 
- In LDP, creation of streaming tables is supported using `CREATE STREAMING TABLE`
- `CREATE OR REFRESH OBJECT <OBJECT NAME>` to create one of streaming tables, materialized views, and temporary views
- same objects can be created in python using the decorators `@dp.table`, `@dp.materialized_view`, `@dp.temporary_view`

### streaming tables

  - are persisted to the catalog
  - can handle incremental refresh
  - are used for data ingestion from append-only streaming sources (`spark.readStream` or `STREAM()` sql function)
  - support NRT ingestion

### materialized views

  - are persisted to the catalog
  - can handle full or sometimes incremental (only on serverless)
  - are used for precomputing complex queries, or for data ingestion **from non-streamable sources (uses `spark.read`)**
  - are _not_ designed for low latency use cases

### temp views 

  - are temp objects scoped to the pipeline they are part of.
  - handle temporarily processed data
  - are used for intermediate transforms and DQ checks

### Comparing LDP to DLT  

- previously, used `import dlt`, and decorator was `@dlt.table` for streaming tables and mat view. The returned dataframe determined the type, whether it was a streaming dataframe, (returns `spark.readStream` method), or a static dataframe (returns `spark.read`)
- temp views used `@dlt.view` decorator
- DLT used notebooks, and could be validated using the validate button in the notebook - LDP uses scripts with `.py` or `.sql` extension, and we can run a dry run to validate the source code without updating data.

## Creating an LDP

- Building on the same example. Going to create the bronze table as a streaming table, and the country lookup table as a temp view.
- `Jobs & Pipelines` > `Create` > `ETL pipeline`
- Select default catalog and schema (or create a new one)
- When creating an empty file pipeline, a default folder structure with `transformations/` dir is created - can be renamed.
- Can also define 'exploration notebook' files and files which contain reusable python functionality
  - Artifacts can be included/excluded from the repo in the file browser
- In pipeline settings, you can set 
  - `pipeline mode` (triggered or continuous)
  - default `catalog` and `schema`
  - `compute type`
  - under `configuration` you can set parameters, key:value pairs like `dataset_path`: `/Volumes/workspace/etc/etc`
  - under `advanced settings` you can define a table to store event logs for the pipeline
- first stage of pipeline defined:
    ```
    from pyspark import pipelines as dp
    from pyspark.sql import functions as F

    dataset_path = spark.conf.get("dataset_path") # <- read dataset_path param from the settings

    @dp.table(
        name = "bronze",
        partition_cols=["topic", "year_month"],
        table_properties={
            "delta.appendOnly": "true", # <- disable updates and deletes
            "pipelines.reset.allowed": "false", # <- disable full rebuild of table from source
        }
    )
    def process_bronze():
        schema = "key BINARY, value BINARY, topic STRING, partition LONG, offset LONG, timestamp LONG"

        bronze_df = (spark.readStream
                        .format("cloudFiles")
                        .option("cloudFiles.format", "json")
                        .schema(schema)
                        .load(f"{dataset_path}/kafka-raw-etl")
                        .withColumn("timestamp", (F.col("timestamp")/1000).cast("timestamp"))  
                        .withColumn("year_month", F.date_format("timestamp", "yyyy-MM"))
                    )

        return bronze_df


    @dp.temporary_view # <- temp view
    def country_lookup():
        countries_df = spark.read.json(f"{dataset_path}/country_lookup")
        return countries_df
    ```
- Running the pipeline will create the tables, process the data. When you run, it runs in 'development mode' which keeps a cluster up - you can disable this by using 'Run with different settings' and turning off the development mode toggle. Running from Monitoring page will also run in 'production' mode

## Expectations

- Quality constraint that validate data as it flow through ETL pipelines
- Expressed in SQL as `CREATE OR REFRESH OBJECT <object_name> (CONSTRAINT <constraint_name> EXPECT (condition))`
- Viloation of the expectaiton will be tracked and reporting in metrics
- By default, records violating the expecation will be kept in the table. `ON VIOLATION <ACTION>` can be defined, to either remove records or cause the pipeline to fail
- Expectations are also supported in Python
    ```
    @dp.table
    @dp.expect("recent_status", "status = 'ACTIVE' AND date >= '2026-01-01'")
    @dp.expect_or_drop("positive_value", "value > 0")
    @dp.expect_or_fail("valid_id", "id IS NOT NULL")
    def my_table():
        spark.readStream.table("source")
    ```
- And in SQL:
    ```
    CREATE OR REFRESH STREAMING TABLE my_table (
        CONSTRAINT recent_status EXPECT ("status = 'ACTIVE' AND date >= '2026-01-01'")
        CONSTRAINT positive_value EXPECT ("positive_value", "value > 0") ON VIOLATION DROP ROW
        CONSTRAINT valid_id EXPECT ("valid_id", "id IS NOT NULL") ON VIOLATION FAIL UPDATE
    )
    AS SELECT * FROM STREAM(source)
    ```
- Can define multiple in a dict and specify collective actions
    ```
    constraints = {"constraint1": "condition1", "constraint2": "condition2"}

    @dp.expect_all(constraints)
    @dp.expect_all_or_drop(constraints)
    @dp.expect_all_or_fail(constraints)
    ```
- Summary of actions and syntax (use `_all` options when passing multiple constraints in a `dict()`):
  |Action|SQL|Python|
  |------|---|------|
  |Warn (default)|EXPECT (...)| `dp.expect`, `dp.expect_all`|
  |Drop|EXPECT (...) ON VIOLATION DROP ROW| `dp.expect_or_drop`, `dp.expect_all_or_drop`|
  |Fail|EXPECT (...) ON VIOLATION FAIL UPDATE| `dp.expect_or_fail`, `dp.expect_all_or_fail`|
- If dropping records that violate a constraint, but still want to track them, quarantine by setting up another `db.expect_or_drop` with the condition that covers the dropped records to capture them
- Common pattern is to add a bool flag to identify invalid records `.withColumn("is_quarantined", F.expr(quarantine_rules))`, and evaulate the `quarantine_rules = "NOT({0})".format(" AND ").join(constraints.values())` expression.
- Can also partition on this column to physically separte the invalid data into a separate data files in the table dir
- Data preview is not available on temporary views 
- Programatically access the info from the event log table - config this in the `Advanced Settings` on the pipeline (check the `Event Logs > publish event log to UC` checkbox, and provide event log name, catalog and schema) - expectiontions are stored under `flow_progress` events in the `details` json column: `SELECT details:flow_progress:data_quality:expectations FROM catalog.schema.event_log WHERE event_type = 'flow_progress'`

## Auto CDC APIs

- LDP feature to make simplify processing CDC feeds
- Prev used `MERGE` to process CDC and process SCD type 2 updates - MERGE INTO requires "complex" logic to handle out of sequence records, which the auto-cdc APIs handle for us.
- Has native support for SCD type 1 and 2 tables
- SQL syntax:
    ```
    CREATE FLOW flowname AS
    AUTO CDC INTO target_table # <- streaming table, must be already created before execution
    FROM stream(cdc_source_table)
    KEYS (key_field) # <- PK field
    APPLY AS DELETE WHEN operation_type = "DELETE" # <- specify deletion
    SEQUENCE BY sequence_field # <- order how operations should be applied. If multiple required, use a STRUCT expression
    COLUMNS * EXCEPT (operation_type, sequence_field) # <- columns to include, `EXCEPT` will exclude columns
    STORED AS SCD TYPE 1;
    ```
- When you declare the target table, LDP creates 2 objects to manage the processing:
  - a view with the same name as the target table which presents the latest clean state of the data,
  - another table with the same name + `__apply_changes_storage` prefix, which keeps track of the change events and other details to handle out of order records. Includes tombstone markers (to flag deleted rows).
- Can also define in python with `create_auto_cdc_flow()` funciton
- This was supported in the old DLT framework using the `APPLY CHANGES` (sql) `apply_changes()` (python) syntax
- SCD type 2 example (SQL)
    ```
    CREATE OR REFRESH STREAMING TABLE books_silver;

    CREATE FLOW books_flow
    AS AUTO CDC INTO books_silver
    FROM stream(books_raw)
    KEYS (book_id)
    SEQUENCE BY updated
    COLUMNS * EXCEPT (updated)
    STORED AS SCD TYPE 2;
    ```
- Materialized view to persist the latest valid data example (SQL)
    ```
    CREATE OR REFRESH MATERIALIZED VIEW current_books
    AS SELECT book_id, title, author, price
    FROM books_silver
    WHERE __END_AT IS NULL;
    ```
- Streaming table example
    ```
    CREATE OR REFRESH STREAMING TABLE books_sales(
        CONSTRAINT valid_subtotal EXPECT(b.book.subtotal = b.book.quantity * c.price) ON VIOLATION DROP ROW,
        CONSTRAINT valid_total EXPECT(total BETWEEN 0 AND 100000) ON VIOLATION FAIL UPDATE,
        CONSTRAINT valid_date EXPECT(order_timestamp <= current_date() AND year(order_timestamp) >= 2020)
        ) AS SELECT *
    FROM STREAM(orders_silver) AS o,
            LATERAL EXPLODE(o.books) AS b(book)
    INNER JOIN current_books AS c
        ON b.book.book_id = c.book_id;
    ```
- Another Mat view for aggregated stats
    ```
    CREATE OR REFRESH MATERIALIZED VIEW authors_stats
    COMMENT "Aggregated statistics of book sales per author in 5-minute windows"
    SELECT
        author,
        window.start AS window_start,
        window.end AS window_end,
        COUNT("order_id") AS orders_count,
        AVG("quantity") AS avg_quantity
    FROM books_sales
    GROUP BY
    author,
    window(order_timestamp, '5 minutes', '5 minutes', '2 minutes') # <- internval 5 mins, step of 5 mins (i.e. how often a new window starts, so non-overlapping windows), starting offset 2 mins
    ORDER BY
    window_start;
    ```
- `Incremental` hint next to Mat view means it's been incrementally updated, and uses serverless compute. Will attept to incrementally refresh and append the results to the view. Inremental only possible on serverless compute.

## Query performance

- Lots of 'data processed' metrics, as well as duration metrics i.e. wall clock duration (total time from scheduling to end of query, including optimization and file pruing)
- Query profile will show more details - this includes graph view of operators. 
    - Top operators shows most expensive operations in terms of time spent, memory peaks, and number of processed rows
- Query text shows the query - can also see in SQL editor.

## Orchestration

- `dbutils.jobs.taskValues.set()` to pass values between tasks in a job as kv pair
- Can set conditions on this with if/else task, and also access job details like `job.start_time.is_weekday`. All in UTC. 
- Parameters can be defined at task or job level. Job params are automatically pushed down to all tasks. Task param with same name will be automatically overwritten by job param. 
- Reference `{{input.param_name}}` to access values from iterable passed to `for_each`. This is passed into the inputs. https://docs.databricks.com/aws/en/jobs/for-each#parameter-passing

# Deployment and Testing

## Databricks Asset Bundles

- Tool for automating deployment of jobs and pipelines across envs

### Useful commands

- `databricks bundle init [template-name]` to create a new project from a template (built in or bring your own). Options include `default-python`, `default-sql`, `dbt-sql`, `mlops-stacks`
- `databricks bundle validate` to validate bundle is syntactically correct
- `databricks bundle deploy -t <target-name>` to deploy to target env in `-t` flag
- `databricks bundle run <job-name> -t <target-name>` to run a deployed job in a target env
- `databricks bundle generate job --existing-job-id <job-id>` to generate a bundle config for a job, and download the referenced files into the local working dir. Only jobs with notebook tasks are "currently" supported
- `databricks bundle deployment bind <job-resource-name> <existing-job-id>` to link an existing job to a bundle job resource, allowing future deployment to override an existing job (sounds like tf import)

### Working with DABs

- Use git to track changes, ci/cd pipelines to `validate`, and `deploy` jobs
- vscode has a `databricks` extension. uses connection profiles.
- `databricks.yaml` is the main config file for the bundle. contains project settings.
  - `bundle:` includes details about the bundle
  - `targets:` specify envs to deploy the bundles to. set workspace mapping and `root_path`
  - `resources:` for jobs and pipelines.. but recommended to put them in dedicated sub dir under `include:` block. This is like using yaml templates to inject further details by referencing other files.
- Permissions are not copied over when exporting a `job`. Set permissions with `permissions:` block on a job

## Working with Python

- Create file to create arbitrary files and manage code a la py
- Import from other directories by appending those dirs to the `sys.path` variable
    ```
    import sys

    for path in sys.path:
        print(path)

    import os
    sys.path.append(os.path.abspath('../modules'))
    ```
- Can also install python wheels using `pip` command `%pip install ../wheels/lib-1.0.0-py3-none-any.whl`. pip magic command ensures package is insalled on all nodes on the active cluster.

## APIs/cli

- `POST` to `/2.2/jobs/create` to create a job
- `POST` to `2.2/jobs/run-now` to run a job. `{"job_id": 123}` in the body 
- `GET` from `2.2/jobs/runs/get` to get job run details. `run_id` in body
- `databricks clusters start <cluster-id>` to start a cluster
- `databricks fs` to interact with `dbfs` *shudder*
- `databricks secrets create-scope --scope name-of-scope`
- `databricks secrets put --scope name-of-scope --key name-of-secret --string-value secretpa$$word`
- `databricks secrets list --scope name-of-scope`
- `dbutils.secrets.get("name-of-scope", "name-of-secret")`

# Data Governance and Sharing

## Unity Catalog

- when new workspace is created with UC enabled, databricks automatically creates a workspace catalog (same name as the workspace) with a `default` schema. it is assigned specifically to the workspace
- by default, workspaces `users` will have `USE CATALOG` permissions on the catalog
- permissions on the `default` schema for the `users` group are `CREATE FUNCTION`, `CREATE MATERIALIZED VIEW`, `CREATE MODEL`, `CREATE TABLE`, `CREATE VOLUME`, `USE SCHEMA` 
- `Owner` of an object has all privileges on that object. `MANAGE` permission can be granted to enable other users/groups to view/manage privileges, transfer ownership, drop and rename an object. Does not grant data plane access
- Tags can be applied to tables
  - From UI, from governed tags, or with custom tags
  - WITH sql: 
    - `SET TAG ON TABLE <CATALOG>.<SCHEMA>.<TABLE> key = value;`
    - `SET TAG ON TABLE <CATALOG>.<SCHEMA>.<TABLE> key ;` can be key only
    - `ALTER TABLE <CATALOG>.<SCHEMA>.<TABLE> SET TAGS {'key' = 'value', 'key2' = 'value2'}`
- Tags can be applied to columns - Add to column from Overview
- Lakehouse monitoring to calculate quality trends and drift metrics over time
  - Pick `Quality` and `configure` under `Data profiling` section
  - `time series` for quality over time, `snapshot` for metrics over all data at every refresh. `inference` for model drift and performance over time.
  - this creates metrics tables in the schema, `drift metrics` and `profile metrics`, as well as a dashboard.
  - can use this info to create alerts
- `system.billing.usage` to view usage data, uncludes SKU, usage date/time, consumption quantity (DBU/USD), identity_metadata

## Dynamic Views

- Allows identity ACLs to be applied to data in a table at column or row level
- We can `CREATE OR REPLACE VIEW AS SELECT column1, ...` and include `CASE WHEN is_member('group_name') THEN pii_column ELSE 'REDACTED'` to apply rules to columns
- Maps into groups with group names
- To apply rules to rows, similar syntax: `CASE WHEN is_member('privileged_group') THEN TRUE ELSE <CONDITIONS>`, e.g. `CASE WHEN is_member('privileged_group') THEN TRUE ELSE Country = 'France' and row_time >= '2025-01-01'`. Users not in the group will be limited with the clause to restrict data to France records updated after a certain date.
- Views can be layered

## Row Filters and Column Masks

- Unity Catalog now simplifies the above process by supporting row filters and column masks directly on the table itself. So, when querying the table, users automatically see only the rows and columns they are authorized to access.

### Column masks

- To dynamically mask a column in a table, start by defining the masking logic in a user-defined function. For example:
    ```
    CREATE FUNCTION email_mask(email STRING)
    RETURN CASE WHEN is_member('admins_demo') THEN email ELSE 'REDACTED' END;
    ```
- Now, you can apply this function on the column in your table: `ALTER TABLE customers_silver ALTER COLUMN email SET MASK email_mask;`

### Row filters

- to dynamically filter rows in a table, start by defining the filtering logic in a user-defined function. For example:
    ```
    CREATE FUNCTION fr_filter(country STRING)
    RETURN IF(is_member('admins_demo'), true, country="France");
    ```
- Now, you can apply this function as a row filter on the table: `ALTER TABLE customers_silver SET ROW FILTER fr_filter ON (country);`

Note that the `is_member` function tests group membership at the workspace level. To test group membership at the account level in Unity Catalog, use the `is_account_group_member` function instead.

## Delta sharing

- open protocol for secure data sharing.
- data provider and data recipient. provider shares delta lake tables via a delta sharing server, which implements the server side component of the protocol
- You define which recipients have access to which subset of the data on the server.
- Recipient can run any client that implements delta sharing.
- Server evaluates access permissions (I guess in unity?) to evaluate whether access is allowed - if so, it checks underlying files in storage, generates temp urls for accessing those files, and sets them to the client. Client then uses those short-lived links to transform the objects directly from cloud object store. 
- Databricks has an integrated delta sharing server, and access permissions are managed via UC
  ```
  CREATE SHARE share-name;

  ALTER SHARE share-name ADD TABLE table;

  GRANT SELECT ON SHARE share-name TO publisher1;
  ```
- 2 ways to share:
  - databricks to databricks sharing, which enables sharing between databricks clients who use UC
    - collection of tables, views, volumes, notebooks
    - leverages built in auth, no token exchange.
    - table history can be shared by including `WITH HISTORY`, which enables time-travel queries and enable reading of the table with spark structured streaming. Change feed can also be queried. Ensure CDF is enabled _before_ sharing WITH HISTORY.
  - open sharing protocol
    - share data you manage in UC with non-databricks users
    - requires external auth with bearer tokens or oidc federation
- must be `metastore admin` or have `CREATE SHARE` privilege on the metastore
- does not require data replication so no additional storage costs, but may be egress costs if across region or providers.
  - may consider replicating the data to the region where your consumer is
- all data is read only for recipients, and only delta tables are supported.

## Lakehouse federation

- Ingestion copies data from source into databricks
- If you dont want to copy data, you can recieve live data from source using lakehouse federation - allows direct query to multiple sources with no copy.
- Set up connection, create a foreign catalog to register to external database and it's tables
- then when you query, the query is pushed down to source to be executed
- Does not use databricks for querying. Consider mat views on foreign tables or ingesting into the lakehouse.

# Testing and Monitoring

## Pipeline tests

- Two types, `DQ tests` (apply `CHECK` constraints) and `Standard` (test the code logic)
- Standard tests run every time the code is modified.
  - unit testing - testing individual units of code e.g. functions. Enables you to find issues with code earlier in the dev cycle. Testing using `assert`, with bool condition. Check if assumptions remain true when developing code.
  - integration testing - testing interaction between subsystems of an application
  - end to end testing - ensure application can run properly in real world scenarios - closely simulate ux from start to finish
- Can also `assertDataFrameEqual` and `assertSchemaEqual` https://www.databricks.com/blog/simplify-pyspark-testing-dataframe-equality-functions

## Cluster Monitoring

- Admin console to manage user permissions unrestriced cluster creation permissions
- Cluster level permissions in compute, to enable/disable use/editing of the permission
  - `CAN ATTACH TO`, `CAN RESTART` and `CAN MANAGE`
- Several options for logging:
  - Cluster event log shows lifecycle events for the cluster. User and databricks-managed events
    - Log can be filtered by event type
    - Resizing allows you to see scaling timeline for the cluster
    - `json` tab on a log line detail for more details
  - Driver logs give you the logs generated within the cluster. This is where your pipeline logging will be - stdout, stderr, log4j errors. Logfiles can be downloaded by clicking file name
  - Metrics tab shows performance of cluster. Ganglia metrics in here, which provides overall cluster health. Breakdown of cluster health, memory, CPU and network.
    - at the bottom, breakdown of the same stats for each node
    - live metrics only available when cluster is running, but databricks captures in snapshot files in Metrics tab - just pictures.

