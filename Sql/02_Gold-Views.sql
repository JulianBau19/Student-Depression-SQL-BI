--STAGE 3: GOLD 

-- Group of data ready to use in BI, tableau, etc..
--Conditions:
--No duplicate values, no invalid values (flags = 1), check, fast to use, stable.


--Step 1 No duplicate values
-- we ll use ROWNUMBER over partition by row_hash to keep only the first value.

-- (Opcional) See how many duplicated values we have
;WITH R AS (
  SELECT row_hash,
         ROW_NUMBER() OVER (PARTITION BY row_hash ORDER BY cln_id) AS rn
  FROM dbo.cln_students
)
SELECT COUNT(*) AS dup_rows FROM R WHERE rn > 1;


-- NOW WE CREATE GOLD TABLE (CLEAN AND READY TO USE)
IF OBJECT_ID('dbo.fact_students') IS NOT NULL
    DROP TABLE dbo.fact_students;

;WITH R AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY row_hash ORDER BY cln_id) AS rn
  FROM dbo.cln_students
)
SELECT
  cln_id,                    -- conservated clean ID
  Gender, Age,
  Academic_Pressure, Study_Satisfaction,
  Sleep_Duration, Sleep_Hours,
  Dietary_Habits,
  Suicidal_Thoughts, Study_Hours,
  Financial_Stress, Family_History, Depression,
  row_hash                  -- KEEP the hash GOLD is usefull
INTO dbo.fact_students
FROM R
WHERE rn = 1                          -- delete the duplicated values
  AND Flag_Age_OutOfRange = 0
  AND Flag_StudyHours_OutOfRange = 0
  AND Flag_AP_Invalid = 0
  AND Flag_SS_Invalid = 0
  AND Flag_FS_Invalid = 0
  AND Flag_Suicidal_Invalid = 0
  AND Flag_FamilyHistory_Invalid = 0
  AND Flag_Depression_Invalid = 0
  AND Flag_Sleep_Unmapped = 0;        -- keep only valid files

--fast check
SELECT COUNT(*) AS rows_gold FROM dbo.fact_students;
SELECT TOP (5) * FROM dbo.fact_students;


--step 2: add constraints
--constaints prevents insert BAD data in the future

-- RULES
ALTER TABLE dbo.fact_students
  ADD CONSTRAINT CK_fact_AP     CHECK (Academic_Pressure BETWEEN 1 AND 5),
      CONSTRAINT CK_fact_SS     CHECK (Study_Satisfaction BETWEEN 1 AND 5),
      CONSTRAINT CK_fact_FS     CHECK (Financial_Stress BETWEEN 1 AND 5),
      CONSTRAINT CK_fact_Age    CHECK (Age BETWEEN 15 AND 35),
      CONSTRAINT CK_fact_Hours  CHECK (Study_Hours BETWEEN 0 AND 24),
      CONSTRAINT CK_fact_Sleep  CHECK (Sleep_Hours BETWEEN 0 AND 24);





--FINAL CHECK TO IMPORT TO BI/TABLEAU


-- 1) ¿How many files are in GOLD?
SELECT COUNT(*) AS rows_gold FROM dbo.fact_students;

-- 2) ¿Constraints apply?
EXEC sp_helpconstraint 'dbo.fact_students';

-- 3) ¿Duplicated values?
SELECT COUNT(*) AS dup_hash
FROM dbo.fact_students
GROUP BY row_hash
HAVING COUNT(*) > 1;

-- 4) ¿NULL values anywhere?
SELECT
  SUM(CASE WHEN Academic_Pressure  IS NULL THEN 1 ELSE 0 END) AS null_AP,
  SUM(CASE WHEN Study_Satisfaction IS NULL THEN 1 ELSE 0 END) AS null_SS,
  SUM(CASE WHEN Financial_Stress   IS NULL THEN 1 ELSE 0 END) AS null_FS,
  SUM(CASE WHEN Sleep_Hours        IS NULL THEN 1 ELSE 0 END) AS null_Sleep
FROM dbo.fact_students;



select * from dbo.fact_students
order by cln_id asc




 


--FINAL STEP FOR CONSUME VIEW IN POWER BI 

IF OBJECT_ID('dbo.vw_students_bi') IS NOT NULL
  DROP VIEW dbo.vw_students_bi;


GO
CREATE VIEW dbo.vw_students_bi AS
SELECT
  -- Stable ID
  cln_id                                   AS StudentID,

  -- Dimensiones limpias
  Gender,
  Age,  
  Dietary_Habits AS [Dietary Habits],
  Sleep_Duration AS [Sleep Duration],
  Sleep_Hours AS [Sleep Hours],
  Academic_Pressure AS [Academic Pressure],
  Study_Satisfaction AS [Study Satisfaction],
  Study_Hours AS [Study Hours],
  Financial_Stress as [Financial Stress],

  -- Bandas útiles para segmentar
  CASE
    WHEN Sleep_Hours IS NULL      THEN 'Unknown'
    WHEN Sleep_Hours < 6          THEN 'Short <6h'
    WHEN Sleep_Hours BETWEEN 6 AND 8 THEN 'Normal 6–8h'
    WHEN Sleep_Hours > 8          THEN 'Long >8h'
  END AS SleepBand,

  CASE
    WHEN Academic_Pressure IS NULL THEN 'Unknown'
    WHEN Academic_Pressure <= 2    THEN 'Low (1–2)'
    WHEN Academic_Pressure = 3     THEN 'Medium (3)'
    WHEN Academic_Pressure >= 4    THEN 'High (4–5)'
  END AS PressureBand,

  CASE
    WHEN Study_Satisfaction IS NULL THEN 'Unknown'
    WHEN Study_Satisfaction <= 2    THEN 'Low (1–2)'
    WHEN Study_Satisfaction = 3     THEN 'Medium (3)'
    WHEN Study_Satisfaction >= 4    THEN 'High (4–5)'
  END AS SatisfactionBand,

  -- Booleanos: versión numérica (para % en BI) y etiqueta
  CONVERT(int, Depression)       AS [Depression Num],
  CASE WHEN Depression=1 THEN 'Yes' WHEN Depression=0 THEN 'No' ELSE 'Unknown' END AS DepressionLabel,

  CONVERT(int, Suicidal_Thoughts) AS [Suicidal Num],
  CASE WHEN Suicidal_Thoughts=1 THEN 'Yes' WHEN Suicidal_Thoughts=0 THEN 'No' ELSE 'Unknown' END AS SuicidalLabel,

  CONVERT(int, Family_History)    AS [Family Hist Num],
  CASE WHEN Family_History=1 THEN 'Yes' WHEN Family_History=0 THEN 'No' ELSE 'Unknown' END AS FamilyHistLabel

FROM dbo.fact_students;
GO


select * from dbo.vw_students_bi