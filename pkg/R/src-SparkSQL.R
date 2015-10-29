start.server =
  function(
    opts = NULL,
    work.dir = getwd()){
    spark.home = Sys.getenv("SPARK_HOME")
    opts =
      paste0(
        paste0(
          ifelse(nchar(names(opts)) == 1, "-", "--"),
          names(opts),
          " ",
          map(opts,  ~if(is.null(.)) "" else .)),
        collapse = " ")
    server.cmd =
      paste0(
        "cd ", work.dir, ";",
        spark.home, "/sbin/start-thriftserver.sh", opts)
    retval = system(server.cmd, intern = TRUE)
    if(!is.null(attr(retval, "status")))
      stop("Couldn't start thrift server:", retval)}

stop.server =
  function(){
    spark.home = Sys.getenv("SPARK_HOME")
    system(
      paste0(
        spark.home,
        "/sbin/stop-thriftserver.sh"))}

src_SparkSQL =
  function(
    host =
      first.not.empty(
        Sys.getenv("HIVE_SERVER2_THRIFT_BIND_HOST"),
        "localhost"),
    port =
      first.not.empty(
        Sys.getenv("HIVE_SERVER2_THRIFT_PORT"),
        10000),
    start.server = FALSE,
    server.opts = list()){
    final.env = NULL
    if(start.server) {
      do.call(
        "start.server",
        server.opts)
      final.env = new.env()
      reg.finalizer(
        final.env,
        function(e) {stop.server()},
        onexit = TRUE)}
    src_HS2(host, port, "SparkSQL", final.env)}


# VALUES not supported, client-local file not supported
copy_to.src_SparkSQL =
  function(dest, df, name, ...)
    stop("copy not implemented for SparkSQL, use load_to instead")



ExternalData =
  function(parser, options)
    structure(
      list(parser = parser, options = options),
      class = "ExternalData")

as.ExternalData = function(x, ...) UseMethod("as.ExternalData")

as.ExternalData.ExternalData = identity

as.ExternalData.character =
  function(x, ...)
    switch(
      x,
      csv = CSVExternalData(x, list(...)),
      json = ExternalData("org.apache.spark.sql.json", list(...)),
      parquet = ExternalData("org.apache.spark.sql.parquet", list(...)),
      ExternalData(x, list(...)))

CSVData =
  function(
    url,
    header = TRUE,
    delimiter = ",",
    quote = '"',
    parserLib = c("commons", "univocity"),
    mode = c("PERMISSIVE", "DROPMALFORMED", "FAILFAST"),
    charset = 'UTF-8',
    inferSchema = TRUE,
    comment = "#")
    ExternalData(
      "com.databricks.spark.csv",
      list(
        path = url,
        header = tolower(as.character(header)),
        delimiter = delimiter,
        quote = quote,
        parserLib = match.arg(parserLib),
        mode = match.arg(mode),
        charset = charset,
        inferSchema = tolower(as.character(inferSchema)),
        comment = comment))

JDBCData =
  function(
    url,
    dbtable,
    driver,
    partitionColumn = NULL,
    lowerBound = NULL,
    upperBound = NULL,
    numPartitions = NULL){
    opt.tally = is.null(partitionColumn) + is.null(lowerBound) +
      is.null(upperBound) + is.null(numPartitions)
    stopifnot(opt.tally == 0 || opt.tally == 4)
    ExternalData(
      "org.apache.spark.sql.jdbc",
      url = url,
      dbtable = dbtable,
      driver = driver,
      partitionColumn = partitionColumn,
      lowerBound = lowerBound,
      upperBound = upperBound,
      numPartitions = numPartitions)}

load_to.src_SparkSQL =
  function(
    dest,
    name,
    data,
    temporary = FALSE,
    in.place = FALSE,
    ...) {
    stopifnot(!in.place)
    sql =
      build_sql(
        "CREATE ",
        if(in.place) sql("EXTERNAL "),
        if(temporary) sql("TEMPORARY "),
        "TABLE ", ident(name), " ",
        sql(paste0("USING ", data$parser, " ")),
        "OPTIONS (",
        sql(paste0(names(data$options), " '", as.character(data$options), "'", collapse = ", ")), ")",
        con = dest$con)
    RJDBC::dbSendUpdate(dest$con, sql)
    tbl(dest, name)}


copy_to_from_local =
  function(src, x, name) {
    tmpdir = tempfile()
    dir.create(tmpdir)
    tmpfile = tempfile(tmpdir = tmpdir)
    write.table(x, file = tmpfile, sep = ",", col.names = TRUE, row.names = FALSE, quote = TRUE)
    load_to(my_db, data = CSVData(url = tmpdir), name = name)}