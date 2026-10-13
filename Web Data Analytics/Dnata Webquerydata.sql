use Dnata

SELECT * FROM WebTrackingData

-- Column-by-column profile

---38097,38097,4415,1-6-2022,08-06-2022
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT PageViewId) AS distinct_pageviewids,
    COUNT(DISTINCT CookieID) AS distinct_cookies,
    MIN(PageViewDate) AS earliest, MAX(PageViewDate) AS latest
FROM WebTrackingData

---Validation

SELECT 
    (COUNT(*) - COUNT(PageViewId)) AS null_PageViewId, 
    (COUNT(*) - COUNT(CookieID)) AS null_CookieID, 
    SUM(CASE WHEN NULLIF(RequestedURL, '') IS NULL THEN 1 ELSE 0 END) AS null_RequestedURL, 
    SUM(CASE WHEN NULLIF(RefererURL, '') IS NULL THEN 1 ELSE 0 END) AS null_RefererURL, 
    (COUNT(*) - COUNT(PageViewDate)) AS null_PageViewDate 
FROM WebTrackingData


SELECT PageViewId, COUNT(*) AS n
FROM WebTrackingData
GROUP BY PageViewId
HAVING COUNT(*) > 1;


SELECT COUNT(*) as c FROM WebTrackingData
WHERE CookieID <= 0  ---202

SELECT COUNT(*) FROM  WebTrackingData
WHERE RequestedURL NOT LIKE 'https://www.abcholidays.com%'


--______________________________________________________________________________________________________________

-- Step 1: Drop the table if it already exists
IF OBJECT_ID('staged', 'U') IS NOT NULL 
    DROP TABLE staged;

-- Step 2: Use a highly optimized CTE that minimizes memory pressure
WITH BasicClean AS (
    SELECT
        PageViewId,
        CookieID,
        RequestedURL,
        RefererURL,
        CAST(PageViewDate AS DATETIME2) AS PageViewDate,
        UserAgent,
        
        -- Compute path_no_locale efficiently
        LOWER(
            CASE 
                WHEN RequestedURL LIKE 'http%://%/gb_en/%' THEN SUBSTRING(RequestedURL, CHARINDEX('/gb_en/', RequestedURL) + 7, 500)
                WHEN RequestedURL LIKE 'http%://%' THEN SUBSTRING(RequestedURL, CHARINDEX('/', RequestedURL, 9) + 1, 500)
                ELSE RequestedURL 
            END
        ) AS path_no_locale,

        -- Campaign details
        NULLIF(CHARINDEX('utm_source=', RequestedURL), 0) AS pos_source,
        NULLIF(CHARINDEX('utm_medium=', RequestedURL), 0) AS pos_medium,
        NULLIF(CHARINDEX('utm_campaign=', RequestedURL), 0) AS pos_campaign
    FROM WebTrackingData
)
SELECT
    PageViewId,
    CookieID,
    RequestedURL,
    RefererURL,
    PageViewDate,
    UserAgent,
    path_no_locale,

    -- PageType Mapping(in a readable formatt)
    CASE
        WHEN RequestedURL LIKE '%/booking/complete/%' THEN 'Booking-Complete'
        WHEN RequestedURL LIKE '%pay-balance/complete%' THEN 'PayBalance-Complete'
        WHEN path_no_locale LIKE 'bookingsignin%' THEN 'Booking-SignIn'
        WHEN path_no_locale LIKE 'bookingalreadydone%' THEN 'Booking-AlreadyDone'
        WHEN path_no_locale LIKE 'holidays/book/%' THEN 'Booking-Checkout'
        WHEN path_no_locale LIKE 'holidays/hotels%' OR path_no_locale LIKE 'hotels%' THEN 'Hotels'
        WHEN path_no_locale LIKE 'holidays/flights%' THEN 'Flights'
        WHEN path_no_locale LIKE 'destination/%' THEN 'Destination'
        WHEN path_no_locale LIKE 'offers/%' THEN 'Offers/Campaign'
        WHEN path_no_locale LIKE 'tours%' THEN 'Tours'
        WHEN path_no_locale LIKE 'things-to-do%' THEN 'Things-To-Do'
        WHEN path_no_locale LIKE 'holiday-extras%' THEN 'Holiday-Extras'
        WHEN path_no_locale LIKE 'holidays/options/%' THEN 'Package-Options'
        WHEN path_no_locale LIKE 'holidays/%' THEN 'Package-Detail'
        WHEN path_no_locale LIKE 'dashboard/bookings%' OR path_no_locale LIKE 'dashboard/booking-details%' THEN 'Dashboard-Bookings'
        WHEN path_no_locale LIKE 'dashboard%' THEN 'Dashboard-Other'
        WHEN path_no_locale LIKE 'pages/%' OR path_no_locale LIKE 'terms%' THEN 'Static/Info'
        WHEN path_no_locale = '' OR path_no_locale LIKE '~?%' ESCAPE '~' THEN 'Home'
        ELSE 'Other'
    END AS PageType,

    -- Referrer Domain Parser 
    CASE
        WHEN RefererURL IS NULL OR RefererURL = '' THEN 'Direct/None'
        WHEN RefererURL LIKE 'http%://%' THEN 
            SUBSTRING(
                RefererURL, 
                CHARINDEX('//', RefererURL) + 2, 
                ISNULL(NULLIF(CHARINDEX('/', RefererURL, CHARINDEX('//', RefererURL) + 2), 0), 257) - (CHARINDEX('//', RefererURL) + 2)
            )
        ELSE RefererURL
    END AS ReferrerDomain,

    -- Device Type Mapping
    CASE
        WHEN UserAgent LIKE '%ipad%' THEN 'Tablet'
        WHEN UserAgent LIKE '%mobile%' OR UserAgent LIKE '%iphone%' OR UserAgent LIKE '%android%' THEN 'Mobile'
        ELSE 'Desktop'
    END AS DeviceType,

    -- Optimized UTM Extractions using pre-calculated positions
    NULLIF(CASE WHEN pos_source IS NOT NULL THEN SUBSTRING(RequestedURL, pos_source + 11, ISNULL(NULLIF(CHARINDEX('&', RequestedURL, pos_source), 0), 2000) - (pos_source + 11)) END, '') AS UTMSource,
    NULLIF(CASE WHEN pos_medium IS NOT NULL THEN SUBSTRING(RequestedURL, pos_medium + 11, ISNULL(NULLIF(CHARINDEX('&', RequestedURL, pos_medium), 0), 2000) - (pos_medium + 11)) END, '') AS UTMMedium,
    NULLIF(CASE WHEN pos_campaign IS NOT NULL THEN SUBSTRING(RequestedURL, pos_campaign + 13, ISNULL(NULLIF(CHARINDEX('&', RequestedURL, pos_campaign), 0), 2000) - (pos_campaign + 13)) END, '') AS UTMCampaign,
    

	-----click-tracking parameter [clicking evidence]
    CAST(CASE WHEN RequestedURL LIKE '%gclid%' THEN 1 ELSE 0 END AS BIT) AS HasGclid,
    CAST(CASE WHEN RequestedURL LIKE '%fbclid%' THEN 1 ELSE 0 END AS BIT) AS HasFbclid,
    CAST(CASE WHEN RequestedURL LIKE '%utm_%' THEN 1 ELSE 0 END AS BIT) AS HasUtm
INTO staged
FROM BasicClean;

select * from staged
_____________________________________________________________________________________________________________
-- 1. Drop the table first if it already exists
IF OBJECT_ID('staged2', 'U') IS NOT NULL 
    DROP TABLE staged2;

-- 2. Create the new table using SELECT INTO
SELECT *,
    CASE
        WHEN RefererURL IS NULL OR RefererURL = '' THEN 'Direct'
        WHEN ReferrerDomain LIKE '%abcholidays.com%' THEN 'Internal Navigation'
        WHEN ReferrerDomain LIKE '%mail.google%' OR ReferrerDomain LIKE '%android.gm%' THEN 'Email'
        
        -- In SQL Server, BIT columns must be explicitly compared to 1
        WHEN ReferrerDomain LIKE '%google%' THEN 
            CASE WHEN HasGclid = 1 OR HasUtm = 1 THEN 'Paid Search' ELSE 'Organic Search' END
            
        WHEN ReferrerDomain LIKE '%bing%' THEN 
            CASE WHEN HasUtm = 1 THEN 'Paid Search' ELSE 'Organic Search' END
            
        WHEN ReferrerDomain LIKE '%facebook%' OR ReferrerDomain LIKE '%instagram%' THEN 
            CASE WHEN HasFbclid = 1 OR HasUtm = 1 THEN 'Paid Social' ELSE 'Organic Social' END --(unpaid)
            
        WHEN ReferrerDomain LIKE '%yahoo%' OR ReferrerDomain LIKE '%duckduckgo%' THEN 'Organic Search'
        WHEN ReferrerDomain LIKE '%abc.com%' THEN 'Partner Referral'
        ELSE 'Other Referral'
    END AS Channel
INTO staged2
FROM staged;

-- 3. Proactively show the data on screen so you can inspect the results immediately
SELECT * FROM staged2 


--__________________________________________________________________________________________________________
-- 1. Drop the table first if it already exists
IF OBJECT_ID('sessionized', 'U') IS NOT NULL 
    DROP TABLE sessionized;

-- 2. Sessionization Logic using CTEs
WITH with_prev AS (
    SELECT *,
        LAG(PageViewDate) OVER (PARTITION BY CookieID ORDER BY PageViewDate) AS PrevPageViewDate
    FROM staged2
),
with_gap AS (
    SELECT *,
        -- SQL Server DATEDIFF syntax (unit, start_date, end_date)
        DATEDIFF(minute, PrevPageViewDate, PageViewDate) AS GapMinutes
    FROM with_prev
)
,with_flag AS (
    SELECT *,
        CASE WHEN PrevPageViewDate IS NULL OR GapMinutes > 30 THEN 1 ELSE 0 END AS NewSessionFlag
    FROM with_gap
)
,with_session_id AS (
    SELECT *,
        SUM(NewSessionFlag) OVER (PARTITION BY CookieID ORDER BY PageViewDate) AS SessionSeq,
        CONCAT(CookieID, '-S', CAST(SUM(NewSessionFlag) OVER (PARTITION BY CookieID ORDER BY PageViewDate) AS VARCHAR(50))) AS SessionId
    FROM with_flag
)
-- 3. Calculate sequence number and insert into the final table
SELECT *,
    ROW_NUMBER() OVER (PARTITION BY SessionId ORDER BY PageViewDate) AS SequenceInSession
INTO sessionized
FROM with_session_id;

-- 4. Instantly view the results
SELECT TOP 100 * FROM sessionized ORDER BY CookieID, PageViewDate;
--__________________________________________________________________________________________________________________
-- =========================================================================
-- 1. DIM_PAGE
-- =========================================================================
IF OBJECT_ID('Dim_Page', 'U') IS NOT NULL DROP TABLE Dim_Page;

SELECT
    -- SQL Server requires an ORDER BY inside OVER()
    ROW_NUMBER() OVER (ORDER BY PageType) AS PageKey,
    PageType,
    CASE
        WHEN PageType IN ('Booking-Checkout','Booking-SignIn','Booking-Complete','Booking-AlreadyDone') THEN 'Booking Funnel'
        WHEN PageType IN ('Hotels','Flights','Destination','Tours','Things-To-Do','Package-Detail','Package-Options','Holiday-Extras') THEN 'Product Browse'
        WHEN PageType IN ('Offers/Campaign','Home') THEN 'Marketing/Landing'
        WHEN PageType IN ('Dashboard-Bookings','Dashboard-Other','PayBalance-Complete') THEN 'Account/Dashboard'
        WHEN PageType = 'Static/Info' THEN 'Content/Support'
        ELSE 'Other'
    END AS PageCategory,
    CASE
        WHEN PageType = 'Booking-Complete' THEN 4
        WHEN PageType = 'Booking-SignIn' THEN 3
        WHEN PageType = 'Booking-Checkout' THEN 2
        WHEN PageType IN ('Hotels','Flights','Destination','Offers/Campaign','Tours','Things-To-Do','Package-Detail','Package-Options','Holiday-Extras') THEN 1
        ELSE 0
    END AS FunnelStage
INTO Dim_Page
FROM (SELECT DISTINCT PageType FROM sessionized) AS src;

select * from Dim_Page
-- =========================================================================
-- 2. DIM_REFERRER
-- =========================================================================
IF OBJECT_ID('Dim_Referrer', 'U') IS NOT NULL DROP TABLE Dim_Referrer;

SELECT 
    ROW_NUMBER() OVER (ORDER BY ReferrerDomain, Channel) AS ReferrerKey, 
    ReferrerDomain, 
    Channel
INTO Dim_Referrer
FROM (SELECT DISTINCT ReferrerDomain, Channel FROM sessionized) AS src;


-- =========================================================================
-- 3. DIM_CAMPAIGN
-- =========================================================================
IF OBJECT_ID('Dim_Campaign', 'U') IS NOT NULL DROP TABLE Dim_Campaign;

SELECT 
    ROW_NUMBER() OVER (ORDER BY UTMSource, UTMMedium, UTMCampaign) AS CampaignKey, 
    UTMSource, 
    UTMMedium, 
    UTMCampaign
INTO Dim_Campaign
FROM (SELECT DISTINCT UTMSource, UTMMedium, UTMCampaign FROM sessionized WHERE UTMCampaign IS NOT NULL) AS src;

select * from Dim_Campaign
-- =========================================================================
-- 4. DIM_DATE (Using a recursive CTE to build out the date calendar loop)
-- =========================================================================
IF OBJECT_ID('Dim_Date', 'U') IS NOT NULL DROP TABLE Dim_Date;

DECLARE @MinDate DATE, @MaxDate DATE;
SELECT @MinDate = MIN(CAST(PageViewDate AS DATE)), @MaxDate = MAX(CAST(PageViewDate AS DATE)) FROM sessionized;

-- Recursive CTE creates the sequence of dates without loops or unnesting
WITH DateList AS (
    SELECT @MinDate AS d
    UNION ALL
    SELECT DATEADD(day, 1, d)
    FROM DateList
    WHERE d < @MaxDate
)
SELECT
    -- Formats date to integer e.g., 20260919
    CAST(CONVERT(VARCHAR(8), d, 112) AS INT) AS DateKey,
    d AS Date,
    YEAR(d) AS Year,
    MONTH(d) AS MonthNum,
    FORMAT(d, 'MMMM') AS MonthName,
    DAY(d) AS Day,
    FORMAT(d, 'dddd') AS DayName,
    -- DATEPART(dw) returns 1 (Sunday) through 7 (Saturday)
    CAST(CASE WHEN DATEPART(dw, d) IN (1, 7) THEN 1 ELSE 0 END AS BIT) AS IsWeekend
INTO Dim_Date
FROM DateList
OPTION (MAXRECURSION 0); -- Prevents errors if your tracking dates span more than 100 days


---___________________________________________________________________________________________________________________________________________________
-- 1. Drop the fact table if it already exists
IF OBJECT_ID('Fact_PageView', 'U') IS NOT NULL 
    DROP TABLE Fact_PageView;

-- 2. Build the Fact Table using SELECT INTO
SELECT
    s.PageViewId,
    s.CookieID,
    s.SessionId,
    -- Handle missing keys by defaulting to NULL or an UNKNOWN key if you have one
    dp.PageKey,
    dr.ReferrerKey,
    dc.CampaignKey,
    
    -- Fixed str time to SQL Server's native date format converter
    CAST(CONVERT(VARCHAR(8), s.PageViewDate, 112) AS INT) AS DateKey,
    
    s.PageViewDate AS PageViewDateTime,
    s.SequenceInSession,
    
    -- Booleans or flags are best stored as BIT or INT
    CAST(CASE WHEN s.SequenceInSession = 1 THEN 1 ELSE 0 END AS BIT) AS IsEntryPage,
    CAST(CASE WHEN s.SequenceInSession = MAX(s.SequenceInSession) OVER (PARTITION BY s.SessionId) THEN 1 ELSE 0 END AS BIT) AS IsExitPage,
    CAST(CASE WHEN s.PageType = 'Booking-Complete' THEN 1 ELSE 0 END AS BIT) AS IsBookingCompletePage,
    
    s.DeviceType
INTO Fact_PageView
FROM sessionized s
LEFT JOIN Dim_Page dp 
    ON s.PageType = dp.PageType
LEFT JOIN Dim_Referrer dr 
    ON s.ReferrerDomain = dr.ReferrerDomain 
    AND s.Channel = dr.Channel
LEFT JOIN Dim_Campaign dc 
    -- Handled the NULL joins safely so rows with missing UTMs still associate correctly if needed, 
    -- or seamlessly map to NULL without breaking query evaluations.
    ON ISNULL(s.UTMSource, '') = ISNULL(dc.UTMSource, '')
    AND ISNULL(s.UTMMedium, '') = ISNULL(dc.UTMMedium, '')
    AND ISNULL(s.UTMCampaign, '') = ISNULL(dc.UTMCampaign, '');

-- 3. Verify the final Fact Table output
SELECT TOP 100 * FROM Fact_PageView ORDER BY SessionId, SequenceInSession;

--________________________________________________________________________________________________________________

-- 1. Rewrite for Dim_Session
DROP TABLE IF EXISTS Dim_Session;

WITH DeviceModeSession AS (
    SELECT 
        SessionId, 
        DeviceType,
        ROW_NUMBER() OVER (PARTITION BY SessionId ORDER BY COUNT(*) DESC) as rn
    FROM sessionized
    GROUP BY SessionId, DeviceType
)
SELECT 
    s.SessionId, 
    s.CookieID, 
    MIN(s.SessionSeq) AS SessionSeq, 
    MIN(s.PageViewDate) AS SessionStart, 
    MAX(s.PageViewDate) AS SessionEnd, 
    DATEDIFF(second, MIN(s.PageViewDate), MAX(s.PageViewDate)) / 60.0 AS SessionDurationMinutes, 
    COUNT(*) AS PageViewCount, 
    m.DeviceType AS DeviceType, 
    MAX(CASE WHEN dp.FunnelStage >= 2 THEN 1 ELSE 0 END) AS ReachedCheckout, 
    MAX(CASE WHEN s.PageType = 'Booking-Complete' THEN 1 ELSE 0 END) AS ConvertedInSession 
INTO Dim_Session
FROM sessionized s 
LEFT JOIN Dim_Page dp ON s.PageType = dp.PageType 
LEFT JOIN DeviceModeSession m ON s.SessionId = m.SessionId AND m.rn = 1
GROUP BY s.SessionId, s.CookieID, m.DeviceType;


-- 2. Rewrite for Dim_Visitor
DROP TABLE IF EXISTS Dim_Visitor;

WITH DeviceModeVisitor AS (
    SELECT 
        CookieID, 
        DeviceType,
        ROW_NUMBER() OVER (PARTITION BY CookieID ORDER BY COUNT(*) DESC) as rn
    FROM sessionized
    GROUP BY CookieID, DeviceType
)
SELECT 
    s.CookieID, 
    MIN(s.PageViewDate) AS FirstSeen, 
    MAX(s.PageViewDate) AS LastSeen, 
    COUNT(*) AS TotalPageViews, 
    MAX(s.SessionSeq) AS TotalSessions, 
    MAX(CASE WHEN s.PageType = 'Booking-Complete' THEN 1 ELSE 0 END) AS EverConverted, 
    m.DeviceType AS PrimaryDeviceType 
INTO Dim_Visitor
FROM sessionized s
LEFT JOIN DeviceModeVisitor m ON s.CookieID = m.CookieID AND m.rn = 1--( choose most used)
GROUP BY s.CookieID, m.DeviceType;


SELECT PageType, COUNT(*) AS n
FROM sessionized
GROUP BY PageType
ORDER BY n DESC;


---------Business Validation

-- Any session that "completed a booking" without ever reaching checkout? Should be impossible.
SELECT COUNT(*) FROM Dim_Session WHERE ConvertedInSession = 1 AND ReachedCheckout = 0;

SELECT SessionId, COUNT(*) AS n FROM Dim_Session GROUP BY SessionId HAVING COUNT(*) > 1

SELECT SessionId, SUM(CAST(IsBookingCompletePage AS INT)) AS n
FROM Fact_PageView
GROUP BY SessionId
HAVING SUM(CAST(IsBookingCompletePage AS INT)) > 1

select * from Fact_PageView
select * from Dim_Campaign
select * from Dim_Date
select* from Dim_Page
select * from Dim_Referrer
select * from Dim_Session
select * from Dim_Visitor

