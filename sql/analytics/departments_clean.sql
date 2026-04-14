CREATE OR REPLACE TABLE `ai-hr-absenteeism-anomaly.analytics.departments_clean` AS
WITH ranked AS (
  SELECT
    department_id,
    department_name,
    TRIM(UPPER(
      CASE department_name
        WHEN 'Finanze' THEN 'Finance'
        WHEN 'H.R.'    THEN 'HR'
        ELSE department_name
      END
    )) AS department_name_clean,
    ROW_NUMBER() OVER (
      PARTITION BY TRIM(UPPER(
        CASE department_name
          WHEN 'Finanze' THEN 'Finance'
          WHEN 'H.R.'    THEN 'HR'
          ELSE department_name
        END
      ))
      ORDER BY department_id ASC
    ) AS rn
  FROM `ai-hr-absenteeism-anomaly.raw.departments`
)
SELECT
  department_id,
  department_name_clean AS department_name
FROM ranked
WHERE rn = 1;
