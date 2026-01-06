SET NOCOUNT ON;
GO

PRINT 'Creating runner procedure...';
GO

IF OBJECT_ID('ctl.sp_mm_run') IS NOT NULL DROP PROCEDURE ctl.sp_mm_run;
GO
CREATE PROCEDURE ctl.sp_mm_run
    @process_name SYSNAME = 'match_merge',
    @threshold FLOAT = 0.8,
    @max_iter INT = 1000,
    @run_id UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @err_msg NVARCHAR(4000);
    EXEC ctl.sp_mm_acquire_lock;
    BEGIN TRY
        EXEC ctl.sp_run_start @process_name = @process_name, @run_id = @run_id OUTPUT;

        EXEC silver.sp_mm_01_stage_new_declarations @run_id = @run_id;
        EXEC silver.sp_mm_02_match_pe @run_id = @run_id;
        EXEC silver.sp_mm_03_match_spe_deterministic @run_id = @run_id;
        EXEC silver.sp_mm_04_match_spe_probabilistic_candidates @run_id = @run_id, @threshold = @threshold;
        EXEC silver.sp_mm_05_build_intrarun_graph @run_id = @run_id, @threshold = @threshold;
        EXEC silver.sp_mm_06_compute_connected_components @run_id = @run_id, @max_iter = @max_iter;
        EXEC silver.sp_mm_07_new_spe_dedup_deterministic @run_id = @run_id;
        EXEC silver.sp_mm_08_new_spe_dedup_probabilistic @run_id = @run_id;
        EXEC mdm.sp_mm_09_merge_spe @run_id = @run_id;
        EXEC mdm.sp_mm_10_merge_pe @run_id = @run_id;
        EXEC mdm.sp_mm_11_merge_relation @run_id = @run_id;

        EXEC ctl.sp_run_end @run_id = @run_id, @status = 'Success';
        EXEC ctl.sp_mm_release_lock;
    END TRY
    BEGIN CATCH
        SET @err_msg = ERROR_MESSAGE();
        EXEC ctl.sp_run_end @run_id = @run_id, @status = 'Failed', @error_message = @err_msg;
        INSERT INTO ctl.process_error(run_id, step_name, error_number, error_message, error_line, error_procedure)
        VALUES(@run_id, 'sp_mm_run', ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        EXEC ctl.sp_mm_release_lock;
        THROW;
    END CATCH
END;
GO
