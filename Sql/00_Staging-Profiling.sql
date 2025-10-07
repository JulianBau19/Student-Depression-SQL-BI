
-- step 1: Staging Table (keep the RAW copy)
-- we'll use this query and step to stage table 

-- Create a new table with the same columns as the original CSV. 
-- All VARCHAR for safety (wont reject weird values)
-- we create that table on DBO schema because it is a small project

-- Right Click in our database, select flatfile, create a new table, then all the data type is nvarchar(100).
select * from [dbo].[stg_students]  -- Stagin table
select * from [dbo].[depressionTable] -- Original Table




select count(*) from [dbo].[stg_students]



--Step 2: Profiling "Understand data quality before changing anything"

--2.1 Quick Sanity Size 
-- Confirm rowcounts and see a few rows.

select count(*) as rows_total from [dbo].[stg_students]
select top(10) * from [dbo].[stg_students]

--2.2 Normalize-on-the-fly helper (no changes yet)
--What: define a common normalization (trim spaces; uppercase where useful).
--Why: empty strings and trailing spaces behave like values unless normalized.
--we'll use CTE in multiple Checks 

--the Next cte is for TRIM the data

WITH N AS (
    SELECT
    LTRIM(RTRIM(Gender))            AS Gender,
    LTRIM(RTRIM(Age))               AS Age_txt,
    LTRIM(RTRIM(Academic_Pressure))  AS AcademicPressure_txt,
    LTRIM(RTRIM(Study_Satisfaction)) AS StudySatisfaction_txt,
    LTRIM(RTRIM(Sleep_Duration))     AS SleepDuration,
    LTRIM(RTRIM(Dietary_Habits))     AS DietaryHabits,
    LTRIM(RTRIM(Have_you_ever_had_suicidal_thoughts))  AS SuicidalThoughts,
    LTRIM(RTRIM(Study_Hours))        AS StudyHours_txt,
    LTRIM(RTRIM(Financial_Stress))   AS FinancialStress_txt,
    LTRIM(RTRIM(Family_History_Of_Mental_Illness))     AS FamilyHistory,
    LTRIM(RTRIM(Depression))        AS Depression
  FROM [dbo].[stg_students])



--2.3 Missingness of Nulls + Empty Strings. Use a SUM(CASE) like an IF-Else in python and then rename the column
SELECT
  SUM(CASE WHEN Gender            IS NULL OR Gender            = '' THEN 1 ELSE 0 END) AS missing_Gender,
  SUM(CASE WHEN Age_txt           IS NULL OR Age_txt           = '' THEN 1 ELSE 0 END) AS missing_Age,
  SUM(CASE WHEN AcademicPressure_txt IS NULL OR AcademicPressure_txt = '' THEN 1 ELSE 0 END) AS missing_AcademicPressure,
  SUM(CASE WHEN StudySatisfaction_txt IS NULL OR StudySatisfaction_txt = '' THEN 1 ELSE 0 END) AS missing_StudySatisfaction,
  SUM(CASE WHEN SleepDuration     IS NULL OR SleepDuration     = '' THEN 1 ELSE 0 END) AS missing_SleepDuration,
  SUM(CASE WHEN DietaryHabits     IS NULL OR DietaryHabits     = '' THEN 1 ELSE 0 END) AS missing_DietaryHabits,
  SUM(CASE WHEN SuicidalThoughts  IS NULL OR SuicidalThoughts  = '' THEN 1 ELSE 0 END) AS missing_SuicidalThoughts,
  SUM(CASE WHEN StudyHours_txt    IS NULL OR StudyHours_txt    = '' THEN 1 ELSE 0 END) AS missing_StudyHours,
  SUM(CASE WHEN FinancialStress_txt IS NULL OR FinancialStress_txt = '' THEN 1 ELSE 0 END) AS missing_FinancialStress,
  SUM(CASE WHEN FamilyHistory     IS NULL OR FamilyHistory     = '' THEN 1 ELSE 0 END) AS missing_FamilyHistory,
  SUM(CASE WHEN Depression        IS NULL OR Depression        = '' THEN 1 ELSE 0 END) AS missing_Depression
FROM N;
-- As we see, 0 null values and 0 Empty values. In case that we have any null or ' ' value we'll treat this in step 3
-- For the moment, we are checking the data not changing it.

--2.4 Count the total values in each column and group by categories

-- Gender (MALE / FEMALE)
;WITH N AS (SELECT UPPER(LTRIM(RTRIM([Gender]))) AS v FROM dbo.stg_students)
SELECT v AS Gender, COUNT(*) AS n
FROM N GROUP BY v ORDER BY n DESC;

-- Dietary Habits
;WITH N AS (SELECT UPPER(LTRIM(RTRIM([Dietary_Habits]))) AS v FROM dbo.stg_students)
SELECT v AS DietaryHabits, COUNT(*) AS n
FROM N GROUP BY v ORDER BY n DESC;

-- Sleep Duration
;WITH N AS (SELECT LTRIM(RTRIM([Sleep_Duration])) AS v FROM dbo.stg_students)
SELECT v AS SleepDuration, COUNT(*) AS n
FROM N GROUP BY v ORDER BY n DESC;

-- Yes/No fields (example: Depression)
;WITH N AS (SELECT UPPER(LTRIM(RTRIM([Depression]))) AS v FROM dbo.stg_students)
SELECT v AS Depression, COUNT(*) AS n
FROM N GROUP BY v ORDER BY n DESC;

--2.5
-- NOW checking if there is any NULL value and check the RANGE of. 
--Ensure they’re numbers and plausible.

;WITH N AS (
  SELECT
    TRY_CONVERT(INT, LTRIM(RTRIM([Age])))          AS Age,
    TRY_CONVERT(INT, LTRIM(RTRIM([Study_Hours])))  AS StudyHours
  FROM dbo.stg_students
)
SELECT
  SUM(CASE WHEN Age IS NULL       THEN 1 ELSE 0 END) AS bad_age_parse,
  SUM(CASE WHEN StudyHours IS NULL THEN 1 ELSE 0 END) AS bad_studyhours_parse,
  SUM(CASE WHEN Age       IS NOT NULL AND (Age < 15 OR Age > 35)   THEN 1 ELSE 0 END) AS age_out_of_range,
  SUM(CASE WHEN StudyHours IS NOT NULL AND (StudyHours < 0 OR StudyHours > 24) THEN 1 ELSE 0 END) AS studyhours_out_of_range
FROM N;



--2.6
-- Now at first we convert the data of 3 columns and check how many values dont fit on the scale 1-5

;WITH N AS (
  SELECT
    TRY_CONVERT(TINYINT, LTRIM(RTRIM([Academic_Pressure])))  AS AP,
    TRY_CONVERT(TINYINT, LTRIM(RTRIM([Study_Satisfaction]))) AS SS,
    TRY_CONVERT(TINYINT, LTRIM(RTRIM([Financial_Stress])))   AS FS
  FROM dbo.stg_students
)
SELECT
  SUM(CASE WHEN AP IS NULL OR AP NOT BETWEEN 1 AND 5 THEN 1 ELSE 0 END) AS bad_AP,
  SUM(CASE WHEN SS IS NULL OR SS NOT BETWEEN 1 AND 5 THEN 1 ELSE 0 END) AS bad_SS,
  SUM(CASE WHEN FS IS NULL OR FS NOT BETWEEN 1 AND 5 THEN 1 ELSE 0 END) AS bad_FS
FROM N;

-- Distributions (helps you see skew)
;WITH N AS (
  SELECT
    TRY_CONVERT(TINYINT, LTRIM(RTRIM([Academic_Pressure])))  AS AP,
    TRY_CONVERT(TINYINT, LTRIM(RTRIM([Study_Satisfaction]))) AS SS,
    TRY_CONVERT(TINYINT, LTRIM(RTRIM([Financial_Stress])))   AS FS
  FROM dbo.stg_students
)
SELECT 'AcademicPressure' AS var, AP AS value, COUNT(*) AS n
FROM N WHERE AP BETWEEN 1 AND 5 GROUP BY AP
UNION ALL
SELECT 'StudySatisfaction', SS, COUNT(*) FROM N WHERE SS BETWEEN 1 AND 5 GROUP BY SS
UNION ALL
SELECT 'FinancialStress',   FS, COUNT(*) FROM N WHERE FS BETWEEN 1 AND 5 GROUP BY FS
ORDER BY var, value;


--Good: all counts in bad_* are zero; distributions only for 1–5.


--2.7 Keep YES/NO strictly (case/space)

select * from dbo.stg_students

;WITH N AS (
  SELECT 
    UPPER(LTRIM(RTRIM([Depression]))) AS Depression,
    UPPER(LTRIM(RTRIM([Have_you_ever_had_suicidal_thoughts]))) AS Suicidal,
    UPPER(LTRIM(RTRIM([Family_History_of_Mental_Illness]))) AS FamHist
  FROM dbo.stg_students
)
SELECT
  SUM(CASE WHEN Depression NOT IN ('YES','NO') THEN 1 ELSE 0 END) AS bad_Depression,
  SUM(CASE WHEN Suicidal   NOT IN ('YES','NO') THEN 1 ELSE 0 END) AS bad_Suicidal,
  SUM(CASE WHEN FamHist    NOT IN ('YES','NO') THEN 1 ELSE 0 END) AS bad_FamilyHistory
FROM N;

--2.8 confirm a finite, clean label set for later numeric mapping.

;WITH N AS (SELECT LTRIM(RTRIM([Sleep_Duration])) AS v FROM dbo.stg_students)
SELECT v AS SleepDuration, COUNT(*) AS n
FROM N
GROUP BY v
ORDER BY n DESC;


