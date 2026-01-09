SET NOCOUNT ON;
GO

PRINT 'Creating DQ functions...';
GO

IF OBJECT_ID('dq.fn_levenshtein') IS NOT NULL
    DROP FUNCTION dq.fn_levenshtein;
GO
CREATE FUNCTION dq.fn_levenshtein(@s1 NVARCHAR(4000), @s2 NVARCHAR(4000))
RETURNS INT
AS
BEGIN
    SET @s1 = ISNULL(@s1, N'');
    SET @s2 = ISNULL(@s2, N'');
    DECLARE @len1 INT = LEN(@s1), @len2 INT = LEN(@s2);
    IF @s1 = @s2 RETURN 0;
    IF @len1 = 0 RETURN @len2;
    IF @len2 = 0 RETURN @len1;

    DECLARE @v0 VARBINARY(MAX) = 0x, @v1 VARBINARY(MAX) = 0x, @i INT = 0, @j INT, @cost INT, @c1 NCHAR(1), @c2 NCHAR(1);

    ;WITH nums AS (
        SELECT TOP (@len2 + 1) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
        FROM sys.all_objects
    )
    SELECT @v0 = @v0 + CAST(n AS BINARY(2)) FROM nums ORDER BY n;

    WHILE @i < @len1
    BEGIN
        SET @c1 = SUBSTRING(@s1, @i + 1, 1);
        SET @v1 = 0x;
        SET @v1 += CAST(@i + 1 AS BINARY(2));
        SET @j = 0;
        WHILE @j < @len2
        BEGIN
            SET @c2 = SUBSTRING(@s2, @j + 1, 1);
            SET @cost = CASE WHEN @c1 = @c2 THEN 0 ELSE 1 END;
            DECLARE @del INT = CAST(SUBSTRING(@v0, (@j + 1) * 2 + 1, 2) AS INT) + 1;
            DECLARE @ins INT = CAST(SUBSTRING(@v1, @j * 2 + 1, 2) AS INT) + 1;
            DECLARE @sub INT = CAST(SUBSTRING(@v0, @j * 2 + 1, 2) AS INT) + @cost;
            DECLARE @val INT = (SELECT MIN(v) FROM (VALUES(@del),(@ins),(@sub)) AS T(v));
            SET @v1 += CAST(@val AS BINARY(2));
            SET @j += 1;
        END
        SET @v0 = @v1;
        SET @i += 1;
    END
    RETURN CAST(SUBSTRING(@v0, @len2 * 2 + 1, 2) AS INT);
END;
GO

IF OBJECT_ID('dq.fn_similarity') IS NOT NULL
    DROP FUNCTION dq.fn_similarity;
GO
CREATE FUNCTION dq.fn_similarity(@s1 NVARCHAR(4000), @s2 NVARCHAR(4000))
RETURNS FLOAT
AS
BEGIN
    IF @s1 IS NULL AND @s2 IS NULL RETURN 1.0;
    IF @s1 IS NULL OR @s2 IS NULL RETURN 0.0;
    DECLARE @len1 INT = LEN(@s1), @len2 INT = LEN(@s2), @maxlen INT = CASE WHEN LEN(@s1) > LEN(@s2) THEN LEN(@s1) ELSE LEN(@s2) END;
    IF @maxlen = 0 RETURN 1.0;
    DECLARE @lev INT = dq.fn_levenshtein(@s1, @s2);
    RETURN 1.0 - (CAST(@lev AS FLOAT) / @maxlen);
END;
GO

IF OBJECT_ID('dq.fn_date_similarity') IS NOT NULL
    DROP FUNCTION dq.fn_date_similarity;
GO
CREATE FUNCTION dq.fn_date_similarity(@d1 DATE, @d2 DATE)
RETURNS FLOAT
AS
BEGIN
    IF @d1 IS NULL AND @d2 IS NULL RETURN 1.0;
    IF @d1 IS NULL OR @d2 IS NULL RETURN 0.0;
    RETURN CASE WHEN @d1 = @d2 THEN 1.0 ELSE 0.0 END;
END;
GO

IF OBJECT_ID('dq.fn_spe_score') IS NOT NULL
    DROP FUNCTION dq.fn_spe_score;
GO
CREATE FUNCTION dq.fn_spe_score
(
    @nom1 NVARCHAR(4000), @nom2 NVARCHAR(4000),
    @prenom1 NVARCHAR(4000), @prenom2 NVARCHAR(4000),
    @dob1 DATE, @dob2 DATE,
    @com1 NVARCHAR(4000), @com2 NVARCHAR(4000)
)
RETURNS FLOAT
AS
BEGIN
    DECLARE @score_nom FLOAT = dq.fn_similarity(@nom1, @nom2);
    DECLARE @score_prenom FLOAT = dq.fn_similarity(@prenom1, @prenom2);
    DECLARE @score_dob FLOAT = dq.fn_date_similarity(@dob1, @dob2);
    DECLARE @score_com FLOAT = dq.fn_similarity(@com1, @com2);
    RETURN (@score_nom + @score_prenom + @score_dob + @score_com) / 4.0;
END;
GO
