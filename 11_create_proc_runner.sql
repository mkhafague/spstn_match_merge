SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE ctl.sp_run_start
    @process_name sysname,
    @run_id uniqueidentifier OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @run_id = NEWID();
    INSERT INTO ctl.process_run (run_id, process_name, start_ts, status, host_name, executed_by)
    VALUES (@run_id, @process_name, SYSUTCDATETIME(), 'Running', HOST_NAME(), SUSER_SNAME());
END;
GO

CREATE OR ALTER PROCEDURE ctl.sp_run_end
    @run_id uniqueidentifier,
    @status varchar(20),
    @error_message nvarchar(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    UPDATE ctl.process_run
    SET end_ts = SYSUTCDATETIME(),
        status = @status,
        error_message = @error_message
    WHERE run_id = @run_id;
END;
GO

CREATE OR ALTER PROCEDURE ctl.sp_log_metric
    @run_id uniqueidentifier,
    @step_name sysname,
    @row_count bigint,
    @duration_ms bigint,
    @comment nvarchar(1000)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    INSERT INTO ctl.process_metrics (run_id, step_name, row_count, duration_ms, comment)
    VALUES (@run_id, @step_name, @row_count, @duration_ms, @comment);
END;
GO

CREATE OR ALTER PROCEDURE ctl.sp_mm_acquire_lock
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @res int;
    EXEC @res = sp_getapplock @Resource = 'MM_RUN', @LockMode = 'Exclusive', @LockTimeout = 0;
    IF @res < 0 THROW 51001, 'Cannot acquire MM_RUN lock', 1;
END;
GO

CREATE OR ALTER PROCEDURE ctl.sp_mm_release_lock
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sp_releaseapplock @Resource = 'MM_RUN';
END;
GO

CREATE OR ALTER PROCEDURE ctl.sp_mm_run
    @process_name sysname = 'match_merge',
    @threshold float = 0.8,
    @run_id uniqueidentifier OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        EXEC ctl.sp_mm_acquire_lock;
        EXEC ctl.sp_run_start @process_name = @process_name, @run_id = @run_id OUTPUT;

        EXEC silver.sp_mm_01_stage_new_declarations @run_id = @run_id;
        EXEC silver.sp_mm_02_match_pe @run_id = @run_id;
        EXEC silver.sp_mm_03_match_spe_deterministic @run_id = @run_id;
        EXEC silver.sp_mm_04_match_spe_probabilistic_candidates @run_id = @run_id, @threshold = @threshold;
        EXEC silver.sp_mm_05_build_intrarun_graph @run_id = @run_id, @threshold = @threshold;
        EXEC silver.sp_mm_06_compute_connected_components @run_id = @run_id;
        EXEC silver.sp_mm_07_new_spe_dedup_deterministic @run_id = @run_id;
        EXEC silver.sp_mm_08_new_spe_dedup_probabilistic @run_id = @run_id;
        EXEC mdm.sp_mm_09_merge_spe @run_id = @run_id;
        EXEC mdm.sp_mm_10_merge_pe @run_id = @run_id;
        EXEC mdm.sp_mm_11_merge_relation @run_id = @run_id;

        EXEC ctl.sp_run_end @run_id = @run_id, @status = 'Success', @error_message = NULL;
        EXEC ctl.sp_mm_release_lock;
    END TRY
    BEGIN CATCH
        DECLARE @err nvarchar(4000) = ERROR_MESSAGE();
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES (@run_id, 'sp_mm_run', ERROR_NUMBER(), @err, ERROR_LINE(), ERROR_PROCEDURE());
        IF @run_id IS NOT NULL
            EXEC ctl.sp_run_end @run_id = @run_id, @status = 'Failed', @error_message = @err;
        EXEC ctl.sp_mm_release_lock;
        THROW;
    END CATCH;
END;
GO
