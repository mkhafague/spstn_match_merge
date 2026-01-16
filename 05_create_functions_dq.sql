SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER FUNCTION dq.fn_levenshtein(@s1 nvarchar(4000), @s2 nvarchar(4000))
RETURNS int
AS
BEGIN
    DECLARE @len1 int, @len2 int;
    DECLARE @i int, @j int, @cost int;
    DECLARE @d TABLE (i int NOT NULL, j int NOT NULL, val int NOT NULL, PRIMARY KEY (i, j));

    IF @s1 IS NULL AND @s2 IS NULL RETURN 0;
    IF @s1 IS NULL RETURN LEN(@s2);
    IF @s2 IS NULL RETURN LEN(@s1);

    SET @len1 = LEN(@s1);
    SET @len2 = LEN(@s2);
    IF @len1 = 0 RETURN @len2;
    IF @len2 = 0 RETURN @len1;
    IF @s1 = @s2 RETURN 0;

    SET @i = 0;
    WHILE @i <= @len1
    BEGIN
        INSERT INTO @d(i, j, val) VALUES (@i, 0, @i);
        SET @i += 1;
    END;

    SET @j = 1;
    WHILE @j <= @len2
    BEGIN
        INSERT INTO @d(i, j, val) VALUES (0, @j, @j);
        SET @j += 1;
    END;

    SET @i = 1;
    WHILE @i <= @len1
    BEGIN
        SET @j = 1;
        WHILE @j <= @len2
        BEGIN
            SET @cost = CASE WHEN SUBSTRING(@s1, @i, 1) = SUBSTRING(@s2, @j, 1) THEN 0 ELSE 1 END;
            DECLARE @del int = (SELECT val FROM @d WHERE i = @i - 1 AND j = @j) + 1;
            DECLARE @ins int = (SELECT val FROM @d WHERE i = @i AND j = @j - 1) + 1;
            DECLARE @sub int = (SELECT val FROM @d WHERE i = @i - 1 AND j = @j - 1) + @cost;
            INSERT INTO @d(i, j, val)
            VALUES (@i, @j, (SELECT MIN(v) FROM (VALUES (@del), (@ins), (@sub)) AS t(v)));
            SET @j += 1;
        END;
        SET @i += 1;
    END;

    RETURN (SELECT val FROM @d WHERE i = @len1 AND j = @len2);
END;
GO

CREATE OR ALTER FUNCTION dq.fn_similarity(@s1 nvarchar(4000), @s2 nvarchar(4000))
RETURNS float
AS
BEGIN
    IF @s1 IS NULL AND @s2 IS NULL RETURN 1.0;
    IF @s1 IS NULL OR @s2 IS NULL RETURN 0.0;
    DECLARE @len1 int = LEN(@s1);
    DECLARE @len2 int = LEN(@s2);
    IF @len1 = 0 AND @len2 = 0 RETURN 1.0;
    IF @len1 = 0 OR @len2 = 0 RETURN 0.0;

    DECLARE @dist int = dq.fn_levenshtein(@s1, @s2);
    DECLARE @maxlen int = CASE WHEN @len1 > @len2 THEN @len1 ELSE @len2 END;
    RETURN 1.0 - (CAST(@dist AS float) / CAST(@maxlen AS float));
END;
GO

CREATE OR ALTER FUNCTION dq.fn_date_similarity(@d1 date, @d2 date)
RETURNS float
AS
BEGIN
    IF @d1 IS NULL AND @d2 IS NULL RETURN 1.0;
    IF @d1 IS NULL OR @d2 IS NULL RETURN 0.0;
    RETURN CASE WHEN @d1 = @d2 THEN 1.0 ELSE 0.0 END;
END;
GO

CREATE OR ALTER FUNCTION dq.fn_spe_score(
    @nom1 nvarchar(200), @nom2 nvarchar(200),
    @prenom1 nvarchar(200), @prenom2 nvarchar(200),
    @dob1 date, @dob2 date,
    @com1 nvarchar(200), @com2 nvarchar(200)
)
RETURNS float
AS
BEGIN
    DECLARE @s_nom float = dq.fn_similarity(@nom1, @nom2);
    DECLARE @s_prenom float = dq.fn_similarity(@prenom1, @prenom2);
    DECLARE @s_dob float = dq.fn_date_similarity(@dob1, @dob2);
    DECLARE @s_com float = dq.fn_similarity(@com1, @com2);
    RETURN (@s_nom + @s_prenom + @s_dob + @s_com) / 4.0;
END;
GO
