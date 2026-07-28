-- LAB513: Search helper objects used in Module 1 and 3

CREATE OR ALTER FUNCTION dbo.SearchFAQ_TVF (
    @Question NVARCHAR(500),
    @TopK INT = 3
)
RETURNS TABLE
AS
RETURN
WITH terms AS (
    SELECT DISTINCT LTRIM(RTRIM(value)) AS term
    FROM STRING_SPLIT(LOWER(@Question), ' ')
    WHERE LEN(LTRIM(RTRIM(value))) > 1
),
scores AS (
    SELECT
        fc.id AS content_id,
        fc.category,
        fc.question,
        fc.answer,
        SUM(
            CASE WHEN LOWER(fc.question) LIKE '%' + terms.term + '%' THEN 3 ELSE 0 END +
            CASE WHEN LOWER(fc.answer) LIKE '%' + terms.term + '%' THEN 1 ELSE 0 END +
            CASE WHEN LOWER(fc.category) LIKE '%' + terms.term + '%' THEN 2 ELSE 0 END
        ) AS raw_score
    FROM dbo.FAQ_Content fc
    LEFT JOIN terms ON 1 = 1
    GROUP BY fc.id, fc.category, fc.question, fc.answer
),
ranked AS (
    SELECT
        content_id,
        category,
        question,
        answer,
        CAST(raw_score AS FLOAT) AS similarity_score
    FROM scores
)
SELECT TOP (@TopK)
    content_id,
    category,
    question,
    answer,
    similarity_score
FROM ranked
ORDER BY similarity_score DESC, content_id ASC;
GO

CREATE OR ALTER PROCEDURE dbo.SearchFAQ
    @Question NVARCHAR(500),
    @TopK INT = 3
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        content_id,
        category,
        question,
        answer,
        similarity_score
    FROM dbo.SearchFAQ_TVF(@Question, @TopK)
    ORDER BY similarity_score DESC, content_id ASC;
END;
GO
