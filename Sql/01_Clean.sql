-- Step 3: The cleaning (typed and standarized)
--what we'r going to look: correct types of data, clean labels, consistent booleans, 2 visions of sleep hours ("5-6 hours" for bi and 
--5.5 for data analysis),row_hash.

select * from dbo.stg_students


--Chosen Types of data that we'll use and why:
--Tinyint for scales 1-5 (low memory use)
--bit for yes/no (faster filters)
--int for age and study_Hours (for numeric operations)
--Decimal (3,1) for sleepHours (for use 4.5,5.5,7.5 for better control)
--NVARCHAR for labels (Gender,Dietay_habits,Sleep_Duration


--STEP 1: Create a clean table with all the FIT data type


CREATE TABLE dbo.cln_students (
  cln_id              INT IDENTITY(1,1) NOT NULL PRIMARY KEY,

  -- FIELDS (limpios/typed)
  Gender              NVARCHAR(10) NULL,       -- 'Male' / 'Female'
  Age                 INT NULL,                -- p. ej. 15..30
  Academic_Pressure    TINYINT NULL,            -- 1..5
  Study_Satisfaction   TINYINT NULL,            -- 1..5
  Sleep_Duration       NVARCHAR(30) NULL,       -- Original label (legible)
  Sleep_Hours          DECIMAL(3,1) NULL,       -- Numeric (midpoint)
  Dietary_Habits       NVARCHAR(20) NULL,       -- 'Healthy'/'Moderate'/'Unhealthy'
  Suicidal_Thoughts    BIT NULL,                -- 1=Yes, 0=No
  Study_Hours          INT NULL,                -- 0..24 tipic
  Financial_Stress     TINYINT NULL,            -- 1..5
  Family_History       BIT NULL,                -- 1=Yes, 0=No
  Depression          BIT NULL,                -- 1=Yes, 0=No

  -- Flags "SOFT" for QA (1 = something ODD)
  Flag_Age_OutOfRange           BIT NOT NULL DEFAULT 0,
  Flag_StudyHours_OutOfRange    BIT NOT NULL DEFAULT 0,
  Flag_AP_Invalid               BIT NOT NULL DEFAULT 0,
  Flag_SS_Invalid               BIT NOT NULL DEFAULT 0,
  Flag_FS_Invalid               BIT NOT NULL DEFAULT 0,
  Flag_Suicidal_Invalid         BIT NOT NULL DEFAULT 0,
  Flag_FamilyHistory_Invalid    BIT NOT NULL DEFAULT 0,
  Flag_Depression_Invalid       BIT NOT NULL DEFAULT 0,
  Flag_Sleep_Unmapped           BIT NOT NULL DEFAULT 0,

  -- Hash para deduplicación y control de cambios
  row_hash VARBINARY(32) NULL
);


--STEP 2:
--CTE S: Clean and represent the text (trim/upper). Upper only for columns that we'll MAP later

;WITH S AS (
  SELECT
    UPPER(LTRIM(RTRIM([Gender])))                                 AS GenderRaw, --Upper because we are going to map this column later
    LTRIM(RTRIM([Age]))                                           AS AgeRaw,
    LTRIM(RTRIM([Academic_Pressure]))                             AS APRaw,
    LTRIM(RTRIM([Study_Satisfaction]))                            AS SSRaw,
    UPPER(LTRIM(RTRIM([Sleep_Duration])))                                AS SleepRaw,  --Upper because we are going to map this column later
    UPPER(LTRIM(RTRIM([Dietary_Habits])))                         AS DietRaw, --Upper because we are going to map this column later
    UPPER(LTRIM(RTRIM([Have_you_ever_had_suicidal_thoughts])))  AS SuicidalRaw, --Upper because we are going to map this column later
    LTRIM(RTRIM([Study_Hours]))                                   AS StudyHoursRaw,
    LTRIM(RTRIM([Financial_Stress]))                              AS FSRaw,
    UPPER(LTRIM(RTRIM([Family_History_of_Mental_Illness])))       AS FamilyRaw, --Upper because we are going to map this column later
    UPPER(LTRIM(RTRIM([Depression])))                             AS DepressionRaw --Upper because we are going to map this column later
  FROM dbo.stg_students
)

select top(5) * from S -- just to check


--CTE P: Parse, maps and flags
-- convert text to num/bit, maps labels to create categories, flags to realize fake or true value.

-- RULES TO APPLY:
--GENDER: CANONIC LABEL
-- Age : INT and a flag range between 15 and 35 (typic age of students)
-- Studyhours: INT and a flag if < 0 or > 24 (0 to 24hours is valid)
-- Academic preassure, Study satisfaction, financial stress: TINYINT and flag if not in range [1,5]
-- Suicidal, FamilyHistory, Depression : YES/NO booleans TO bit 0/1. Flag if we get any other result.
--DietaryHabits: TITTLE CASE and CANONIC (only 3 results)
--Sleep Duration: unique LABEL and take care of sleephours (midpoint(like a average)).

select top(5) * from stg_students

;WITH S AS (
  SELECT
    UPPER(LTRIM(RTRIM([Gender])))                                 AS GenderRaw,
    LTRIM(RTRIM([Age]))                                           AS AgeRaw,
    LTRIM(RTRIM([Academic_Pressure]))                             AS APRaw,
    LTRIM(RTRIM([Study_Satisfaction]))                            AS SSRaw,
    LTRIM(RTRIM([Sleep_Duration]))                                AS SleepRaw,
    UPPER(LTRIM(RTRIM([Dietary_Habits])))                         AS DietRaw,
    UPPER(LTRIM(RTRIM([Have_you_ever_had_suicidal_thoughts])))  AS SuicidalRaw,
    LTRIM(RTRIM([Study_Hours]))                                   AS StudyHoursRaw,
    LTRIM(RTRIM([Financial_Stress]))                              AS FSRaw,
    UPPER(LTRIM(RTRIM([Family_History_of_Mental_Illness])))       AS FamilyRaw,
    UPPER(LTRIM(RTRIM([Depression])))                             AS DepressionRaw
  FROM dbo.stg_students
),
P AS (
  SELECT
    -- 1) CANONIC CATEGORY
    CASE WHEN GenderRaw IN ('MALE','M') THEN 'Male'
         WHEN GenderRaw IN ('FEMALE','F') THEN 'Female'
         ELSE NULL END                                             AS Gender,

    CASE WHEN DietRaw IN ('HEALTHY','MODERATE','UNHEALTHY')
         THEN CONCAT(UPPER(LEFT(DietRaw,1)), LOWER(SUBSTRING(DietRaw,2,50)))
         ELSE NULL END                                             AS DietaryHabits,

    -- 2) NUMBERS (TRY_CONVERT => If Fails, NULL)
    TRY_CONVERT(INT, AgeRaw)                                      AS Age,
    TRY_CONVERT(INT, StudyHoursRaw)                                AS StudyHours,

    -- PARCHE here. At first try to convert the number in decimal and replace ',' and '.'
    -- 2nd ROUND the number.. "2.3 to 2" or "4.5 to 5".  if we cant convert the number then NULL
    -- 3th RANGE between 1 to 5 
    TRY_CONVERT(TINYINT,
  CASE
    WHEN TRY_CONVERT(DECIMAL(4,2), REPLACE(APRaw, ',', '.')) IS NULL THEN NULL
    ELSE
      CASE
        WHEN ROUND(TRY_CONVERT(DECIMAL(4,2), REPLACE(APRaw, ',', '.')), 0) < 1 THEN 1
        WHEN ROUND(TRY_CONVERT(DECIMAL(4,2), REPLACE(APRaw, ',', '.')), 0) > 5 THEN 5
        ELSE TRY_CONVERT(INT, ROUND(TRY_CONVERT(DECIMAL(4,2), REPLACE(APRaw, ',', '.')), 0))
      END
  END
) AS AP_val,

-- SS
TRY_CONVERT(TINYINT,
  CASE
    WHEN TRY_CONVERT(DECIMAL(4,2), REPLACE(SSRaw, ',', '.')) IS NULL THEN NULL
    ELSE
      CASE
        WHEN ROUND(TRY_CONVERT(DECIMAL(4,2), REPLACE(SSRaw, ',', '.')), 0) < 1 THEN 1
        WHEN ROUND(TRY_CONVERT(DECIMAL(4,2), REPLACE(SSRaw, ',', '.')), 0) > 5 THEN 5
        ELSE TRY_CONVERT(INT, ROUND(TRY_CONVERT(DECIMAL(4,2), REPLACE(SSRaw, ',', '.')), 0))
      END
  END
) AS SS_val,

-- FS (si también puede venir con decimales)
TRY_CONVERT(TINYINT,
  CASE
    WHEN TRY_CONVERT(DECIMAL(4,2), REPLACE(FSRaw, ',', '.')) IS NULL THEN NULL
    ELSE
      CASE
        WHEN ROUND(TRY_CONVERT(DECIMAL(4,2), REPLACE(FSRaw, ',', '.')), 0) < 1 THEN 1
        WHEN ROUND(TRY_CONVERT(DECIMAL(4,2), REPLACE(FSRaw, ',', '.')), 0) > 5 THEN 5
        ELSE TRY_CONVERT(INT, ROUND(TRY_CONVERT(DECIMAL(4,2), REPLACE(FSRaw, ',', '.')), 0))
      END
  END
) AS FS_val,

    -- 3) BOOLEANS (YES/NO -> BIT)
    CASE WHEN SuicidalRaw  IN ('YES','Y') THEN CAST(1 AS BIT)
         WHEN SuicidalRaw  IN ('NO','N')  THEN CAST(0 AS BIT)
         ELSE NULL END                                             AS SuicidalThoughts,

    CASE WHEN FamilyRaw    IN ('YES','Y') THEN CAST(1 AS BIT)
         WHEN FamilyRaw    IN ('NO','N')  THEN CAST(0 AS BIT)
         ELSE NULL END                                             AS FamilyHistory,

    CASE WHEN DepressionRaw IN ('YES','Y') THEN CAST(1 AS BIT)
         WHEN DepressionRaw IN ('NO','N')  THEN CAST(0 AS BIT)
         ELSE NULL END                                             AS Depression,

    -- 4) SleepHours: Label + Hours (midpoint)
    SleepRaw,
    CASE UPPER(SleepRaw)
      WHEN 'LESS THAN 5 HOURS' THEN 4.5
      WHEN '5-6 HOURS'         THEN 5.5
      WHEN '7-8 HOURS'         THEN 7.5
      WHEN 'MORE THAN 8 HOURS' THEN 8.5
      ELSE NULL
    END                                                           AS SleepHours,

    -- 5) FLAGS (REGLAS SOFT)
    -- Range of age
    CASE WHEN TRY_CONVERT(INT, AgeRaw) IS NOT NULL --At first i convert the AGE RAW value into A INT
              AND (TRY_CONVERT(INT, AgeRaw) < 15 OR TRY_CONVERT(INT, AgeRaw) > 35) -- Then i compare this value between 2 values 15 and 30
         THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END               AS Flag_Age_OutOfRange, -- If the value is not in this range then a create a new column named flag age outofrange.
                                                                                           -- 1 is bad and 0 is GOOD.
    -- Range of hours
    CASE WHEN TRY_CONVERT(INT, StudyHoursRaw) IS NOT NULL
              AND (TRY_CONVERT(INT, StudyHoursRaw) < 0 OR TRY_CONVERT(INT, StudyHoursRaw) > 24)
         THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END               AS Flag_StudyHours_OutOfRange,

    -- Likert 1..5
CASE WHEN TRY_CONVERT(DECIMAL(4,2), REPLACE(APRaw, ',', '.')) IS NULL
       OR TRY_CONVERT(DECIMAL(4,2), REPLACE(APRaw, ',', '.')) NOT BETWEEN 1 AND 5
     THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END               AS Flag_AP_Invalid,

CASE WHEN TRY_CONVERT(DECIMAL(4,2), REPLACE(SSRaw, ',', '.')) IS NULL
       OR TRY_CONVERT(DECIMAL(4,2), REPLACE(SSRaw, ',', '.')) NOT BETWEEN 1 AND 5
     THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END               AS Flag_SS_Invalid,

CASE WHEN TRY_CONVERT(DECIMAL(4,2), REPLACE(FSRaw, ',', '.')) IS NULL
       OR TRY_CONVERT(DECIMAL(4,2), REPLACE(FSRaw, ',', '.')) NOT BETWEEN 1 AND 5
     THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END               AS Flag_FS_Invalid,

    -- Booleans
    CASE WHEN SuicidalRaw   NOT IN ('YES','Y','NO','N') AND SuicidalRaw IS NOT NULL
         THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END               AS Flag_Suicidal_Invalid,

    CASE WHEN FamilyRaw     NOT IN ('YES','Y','NO','N') AND FamilyRaw IS NOT NULL
         THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END               AS Flag_FamilyHistory_Invalid,

    CASE WHEN DepressionRaw NOT IN ('YES','Y','NO','N') AND DepressionRaw IS NOT NULL
         THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END               AS Flag_Depression_Invalid,

    -- Sleep without map
    CASE WHEN CASE UPPER(SleepRaw)
               WHEN 'LESS THAN 5 HOURS' THEN 4.5
               WHEN '5-6 HOURS'         THEN 5.5
               WHEN '7-8 HOURS'         THEN 7.5
               WHEN 'MORE THAN 8 HOURS' THEN 8.5
               ELSE NULL END IS NULL
         THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END               AS Flag_Sleep_Unmapped
  FROM S
)
--SELECT TOP (5) * FROM P;-- check the columns // i comment this because i need to consume my CTE over



--STEP 3: INSERT INTO THE TABLE


INSERT INTO dbo.cln_students (
  Gender, Age, Academic_Pressure, Study_Satisfaction, Sleep_Duration, Sleep_Hours,
  Dietary_Habits, Suicidal_Thoughts, Study_Hours, Financial_Stress, Family_History, Depression,
  Flag_Age_OutOfRange, Flag_StudyHours_OutOfRange, Flag_AP_Invalid, Flag_SS_Invalid, Flag_FS_Invalid,
  Flag_Suicidal_Invalid, Flag_FamilyHistory_Invalid, Flag_Depression_Invalid, Flag_Sleep_Unmapped,
  row_hash
)
SELECT
  -- Canonic Values but CANCELING the flag ones
  Gender,
  CASE WHEN Flag_Age_OutOfRange=1 THEN NULL ELSE Age END                                  AS Age,
  CASE WHEN Flag_AP_Invalid=1 THEN NULL ELSE AP_val END                                   AS AcademicPressure,
  CASE WHEN Flag_SS_Invalid=1 THEN NULL ELSE SS_val END                                   AS StudySatisfaction,
  SleepRaw                                                                                AS SleepDuration,
  CASE WHEN Flag_Sleep_Unmapped=1 THEN NULL ELSE SleepHours END                           AS SleepHours,
  DietaryHabits,
  CASE WHEN Flag_Suicidal_Invalid=1 THEN NULL ELSE SuicidalThoughts END                   AS SuicidalThoughts,
  CASE WHEN Flag_StudyHours_OutOfRange=1 THEN NULL ELSE StudyHours END                    AS StudyHours,
  CASE WHEN Flag_FS_Invalid=1 THEN NULL ELSE FS_val END                                   AS FinancialStress,
  CASE WHEN Flag_FamilyHistory_Invalid=1 THEN NULL ELSE FamilyHistory END                 AS FamilyHistory,
  CASE WHEN Flag_Depression_Invalid=1 THEN NULL ELSE Depression END                       AS Depression,

  -- Flags
  Flag_Age_OutOfRange, Flag_StudyHours_OutOfRange, Flag_AP_Invalid, Flag_SS_Invalid, Flag_FS_Invalid,
  Flag_Suicidal_Invalid, Flag_FamilyHistory_Invalid, Flag_Depression_Invalid, Flag_Sleep_Unmapped,

  -- row_hash: Concatenation with separator | and ISNULL for stability
  HASHBYTES('SHA2_256',
    CONCAT(
      ISNULL(Gender,''),'|',
      ISNULL(CONVERT(varchar(10),CASE WHEN Flag_Age_OutOfRange=1 THEN NULL ELSE Age END),''),'|',
      ISNULL(CONVERT(varchar(1), CASE WHEN Flag_AP_Invalid=1 THEN NULL ELSE AP_val END),''),'|',
      ISNULL(CONVERT(varchar(1), CASE WHEN Flag_SS_Invalid=1 THEN NULL ELSE SS_val END),''),'|',
      ISNULL(SleepRaw,''),'|',
      ISNULL(CONVERT(varchar(10),CASE WHEN Flag_Sleep_Unmapped=1 THEN NULL ELSE SleepHours END),''),'|',
      ISNULL(DietaryHabits,''),'|',
      ISNULL(CONVERT(varchar(1), CASE WHEN Flag_Suicidal_Invalid=1 THEN NULL ELSE SuicidalThoughts END),''),'|',
      ISNULL(CONVERT(varchar(2), CASE WHEN Flag_StudyHours_OutOfRange=1 THEN NULL ELSE StudyHours END),''),'|',
      ISNULL(CONVERT(varchar(1), CASE WHEN Flag_FS_Invalid=1 THEN NULL ELSE FS_val END),''),'|',
      ISNULL(CONVERT(varchar(1), CASE WHEN Flag_FamilyHistory_Invalid=1 THEN NULL ELSE FamilyHistory END),''),'|',
      ISNULL(CONVERT(varchar(1), CASE WHEN Flag_Depression_Invalid=1 THEN NULL ELSE Depression END),'')
    )
  ) AS row_hash
FROM P;


-- CHECK THE FINAL SCRIPT!!  


-- Size
SELECT COUNT(*) AS rows_clean FROM dbo.cln_students;  -- Should be 502

-- Sample
SELECT TOP (5) * FROM dbo.cln_students;

-- QA view
SELECT
  SUM(CASE WHEN Academic_Pressure IS NULL AND Flag_AP_Invalid=1 THEN 1 ELSE 0 END) AS nulled_AP,
  SUM(CASE WHEN Study_Satisfaction IS NULL AND Flag_SS_Invalid=1 THEN 1 ELSE 0 END) AS nulled_SS,
  SUM(CASE WHEN Financial_Stress  IS NULL AND Flag_FS_Invalid=1 THEN 1 ELSE 0 END) AS nulled_FS
FROM dbo.cln_students;

-- Files with FLAGS for a later check
SELECT *
FROM dbo.cln_students
WHERE Flag_Age_OutOfRange=1
   OR Flag_StudyHours_OutOfRange=1
   OR Flag_AP_Invalid=1
   OR Flag_SS_Invalid=1
   OR Flag_FS_Invalid=1
   OR Flag_Suicidal_Invalid=1
   OR Flag_FamilyHistory_Invalid=1
   OR Flag_Depression_Invalid=1
   OR Flag_Sleep_Unmapped=1;


