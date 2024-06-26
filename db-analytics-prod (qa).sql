USE db-analytics-prod;

-- Step 1: Create New Schemas
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = N'qa')
BEGIN
    EXEC('CREATE SCHEMA qa');
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.name = 'BotActivityLogic' AND s.name = 'qa'
)
BEGIN
    SELECT * INTO qa.BotActivityLogic FROM scratch.BotActivityLogic WHERE 1=0;
END

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.name = 'EmailReportingTA' AND s.name = 'qa'
)
BEGIN
    SELECT * INTO qa.EmailReportingTA FROM scratch.EmailReportingTA WHERE 1=0;
END

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.name = 'EmailStudyBridge' AND s.name = 'qa'
)
BEGIN
    SELECT * INTO qa.EmailStudyBridge FROM scratch.EmailStudyBridge WHERE 1=0;
END

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.name = 'SentEmailsPerStudyPerEmail' AND s.name = 'qa'
)
BEGIN
    SELECT * INTO qa.SentEmailsPerStudyPerEmail FROM scratch.SentEmailsPerStudyPerEmail WHERE 1=0;
END

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.name = 'storedProclog' AND s.name = 'qa'
)
BEGIN
    SELECT * INTO qa.storedProclog FROM scratch.storedProclog WHERE 1=0;
END

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.name = 'tblSentEmailClickDetail' AND s.name = 'qa'
)
BEGIN
    SELECT * INTO qa.tblSentEmailClickDetail FROM scratch.tblSentEmailClickDetail WHERE 1=0;
END

/****** Object:  View [qa].[vw_PatientActivityReporting]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [qa].[vw_PatientActivityReporting] as
--Used for DS-59 Patient Activity Reporting
--leverages patientevent as well as additional tables unioned to consolidate different patient activity log tables

WITH userSessions AS (SELECT UserSessionId, UserId, CreatedDateUtc FROM   ctc.UserSession WHERE  UserId IS NOT NULL)

--Document View CTE (Leverages same logic as [dbo].[v_PatientStudyDocumentView] in ctc
,DocumentViews as (
SELECT 
	 vlv.VersionLanguageviewID
	,d.DocumentId
	,US.UsersessionID
	--Custom Event Type based on Source Table
	,US.UserId
	,d.DocumentName
	,dt.DocumentTypeDescription AS DocumentType
	,v.VersionName
	,l.LanguageName AS VersionLanguageName
	,d.StudyGuid
	,us.CreatedDateUtc
FROM userSessions AS us
INNER JOIN ctc.VersionLanguageView AS vlv ON vlv.UserSessionId = us.UserSessionId
LEFT OUTER JOIN ctc.VersionLanguage AS vl ON vl.VersionLanguageId = vlv.VersionLanguageId
LEFT OUTER JOIN ctc.Version AS v ON v.VersionId = vl.VersionLanguageVersionId
LEFT OUTER JOIN ctc.Document AS d ON d.DocumentId = v.VersionDocumentId
LEFT OUTER JOIN ctc.DocumentType AS dt ON dt.DocumentTypeId = d.DocumentTypeId 
LEFT OUTER JOIN ctc.MediaType AS mt ON mt.MediaTypeId = d.MediaTypeId
LEFT OUTER JOIN ctc.Language AS l ON l.LanguageId = v.VersionLanguageId
)
SELECT  
	   P.[PatientEventId] as ID
      ,CAST(P.[CreatedDateUtc] as date) CreatedDateUTC
      ,P.[DocumentId] as DetailID
      ,P.[UserSessionId]
	  ,E.EventTypeDesc
	  ,S.UserId
	  ,U.UserCountryId
	  ,U.IsDeleted as 'UserDeleted'
	  ,C.SiteStudyID
	  ,D.StudyID
	  --Next two columns Used for distinct Counting and differentiating different tables
	  ,'PatientEvent' as 'SourceTable'
	  ,CONCAT(P.[PatientEventId], '-' , 1 ) as DerivedKey
	  --Used in last union query for supplying document name
	  ,NULL as DetailName
	  ,NULL as VersionName
  FROM ctc.[PatientEvent] P
  JOIN ctc.EventType E on E.EventTypeId = P.EventTypeId
  JOIN ctc.UserSession S on S.UserSessionId = P.UserSessionId
  JOIN ctc.[User] U on U.UserId = S.UserID 
  JOIN ctc.SitePatient SP on SP.UserId = U.UserId
  JOIN cta.tblSiteStudy C ON (C.SiteGuid=SP.SiteGuid AND C.SiteNumber <> '000') --Exclude MySite 
  JOIN qa.vw_StudyReporting D ON (D.StudyID=C.StudyID)
  WHERE 0=0
  --Exclude Deleted Records
  AND P.IsDeleted = 0
  --Exclude Demo Users
  AND U.IsDemo = 0
  --Exclude Inactive Events
  AND E.IsActive = 1
  --Exlcude these Event Types, presumed that they are deprecated or no longer relevant
  AND E.EventTypeDesc NOT IN ('Access Site', 'Accessed Document', 'Account Settings - View', 'Contact Site - View', 'Interested' , 'Not Interested', 'Question' )

 
 UNION ALL

 --SiteStudyVideoChatView
SELECT 
	 V.[SiteStudyVideoChatViewId] as ID
	,CAST(V.[CreatedDateUtc] as date) as [CreatedDateUtc]
	,V.[SiteStudyVideoChatID] as DetailID
	,V.UserSessionId
	--Custom Event Type based on Source Table
	,'Video Chat View' as EventTypeDesc
	,S.UserId
	,U.UserCountryId
	,U.IsDeleted as 'UserDeleted'
	,C.SiteStudyID
	,D.StudyID
	--Next two columns Used for distinct Counting and differentiating different tables
	,'SiteStudyVideoChatView' as 'SourceTable'
	,CONCAT(V.[SiteStudyVideoChatViewId], '-' , 2 ) as DerivedKey
	--Used in last union query for supplying document name
	,NULL as DetailName
	,NULL as VersionName
  FROM [ctc].[SiteStudyVideoChatView] V
  JOIN [ctc].UserSession S on S.UserSessionId = v.UserSessionId
  JOIN ctc.[User] U on U.UserId = S.UserID 
  JOIN ctc.SitePatient SP on SP.UserId = U.UserId
  JOIN cta.tblSiteStudy C ON (C.SiteGuid=SP.SiteGuid AND C.SiteNumber <> '000') --Exclude MySite 
  JOIN qa.vw_StudyReporting D ON (D.StudyID=C.StudyID)
  WHERE 0=0
  --Exclude Deleted Records
  AND V.IsDeleted = 0
  --Exclude Demo Users
  AND U.IsDemo = 0

UNION ALL

--Conversation Messages
SELECT 
	 V.[ConversationMessageViewId] as ID
	,CAST(V.[CreatedDateUtc] as Date) as [CreatedDateUtc]
	,V.ConversationMessageId as DetailID
	,V.UserSessionId
	--Custom Event Type based on Source Table
	,'Conversation Message View' as EventTypeDesc
	,S.UserId
	,U.UserCountryId
	,U.IsDeleted as 'UserDeleted'
	,C.SiteStudyID
	,D.StudyID
	--Next two columns Used for distinct Counting and differentiating different tables
	,'ConversationMessageView' as 'SourceTable'
	,CONCAT(V.[ConversationMessageViewId], '-' , 3 ) as DerivedKey
	--Used in last union query for supplying document name
	,NULL as DetailName
	,NULL as VersionName
FROM [ctc].[ConversationMessageView] V
JOIN ctc.ConversationMessage M on M.ConversationMessageId = V.ConversationMessageId
JOIN ctc.lk_ConversationMessageType T on T.ConversationMessageTypeId = M.ConversationMessageTypeId
JOIN ctc.UserSession S on S.UserSessionId = V.UserSessionId
JOIN ctc.[User] U on U.UserId = S.UserID 
JOIN ctc.SitePatient SP on SP.UserId = U.UserId
JOIN cta.tblSiteStudy C ON (C.SiteGuid=SP.SiteGuid AND C.SiteNumber <> '000') --Exclude MySite 
JOIN qa.vw_StudyReporting D ON (D.StudyID=C.StudyID)
WHERE 0=0
--Exclude Deleted Message Views
	AND C.Isdeleted = 0
--Exclude Demo Users
  AND U.IsDemo = 0
 
UNION ALL

--Patient Document Views
SELECT 
	 V.VersionLanguageviewID as ID
	,CAST( V.CreatedDateUtc as Date) as CreatedDateUtc
	,V.DocumentId as DetailID
	,V.UserSessionId
	--Custom Event Type based on Source Table
	,'Patient Document View' as EventTypeDesc
    ,S.UserId
	,U.UserCountryId
	,U.IsDeleted as 'UserDeleted'
	,C.SiteStudyID
	,D.StudyID
	--Used for distinct Counting and differentiating different tables
	,'VersionLanguageView' as 'SourceTable'  	  
	,CONCAT(V.VersionLanguageviewID, '-' , 4 ) as DerivedKey
	--Used for supplying document name
	,V.DocumentName as DetailName
	--Document Version
	,v.VersionName
  FROM DocumentViews V
  JOIN ctc.UserSession S on S.UserSessionId = V.UserSessionId
  JOIN ctc.[User] U on U.UserId = S.UserID 
  JOIN ctc.SitePatient SP on SP.UserId = U.UserId
  JOIN cta.tblSiteStudy C ON (C.SiteGuid=SP.SiteGuid AND C.SiteNumber <> '000') --Exclude MySite 
  JOIN qa.vw_StudyReporting D ON (D.StudyID=C.StudyID)
  WHERE 0=0
  --Exclude Demo Users
  AND U.IsDemo = 0
GO

/****** Object:  View [qa].[vw_ReferStudyViewReporting]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--Created at: 2022-07-07 12:05:31.457
--SQL User: vgoyal@clinone.com
--Description: ReferStudyView

CREATE VIEW [qa].[vw_ReferStudyViewReporting] as 

--Study View Reporting for DS-43

SELECT
 R.ReferStudyViewID
,R.UserSessionID
,R.StudyID
,R.SiteStudyID
,R.ReferringSpecialistID
,E.Email
,CAST(R.CreatedDateUtc as DATE) as CreatedDateUTC
,CONCAT(R.ReferringSpecialistID, '-' , CAST(R.CreatedDateUTC as date) , '-' , R.StudyID ) as UniqueKeyView
,CONCAT(E.Email, '-' , CAST(R.CreatedDateUTC as date) , '-' , R.StudyID ) as UniqueKeyView2
,US.Duration
FROM cta.tblReferStudyView R
JOIN qa.vw_StudyReporting S on R.StudyID = S.StudyID
JOIN qa.vw_SpecialistReporting E on E.ReferringSpecialistID = R.ReferringSpecialistID
join cta.TblUserSession US on us.UserSessionID = R.UserSessionID
WHERE 0=0
AND S.StudyClientTypeID = 1
--Exclude Records without a recorded Specialist
AND R.ReferringSpecialistID IS NOT NULL
AND R.IsDeleted = 0

GO
/****** Object:  View [qa].[vw_UserSessionreporting]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [qa].[vw_UserSessionreporting] as
--Used to capture landing page view duration for TA Engagement Reporting DS-43
SELECT 
	 U.[UserSessionID]
	 --Logic to Parse Session Duration in Seconds
	,(LEFT(CAST(U.[Duration] as varchar), CHARINDEX(':', CAST(U.[Duration] as varchar)) - 1)  * 60 * 60) + (SUBSTRING(CAST(U.[Duration] as varchar), CHARINDEX(':', CAST(U.[Duration] as varchar)) + 1, 2) * 60) + SUBSTRING(CAST(U.[Duration] as varchar), CHARINDEX(':', CAST(U.[Duration] as varchar)) + 4, 2) + CASE WHEN (SUBSTRING(CAST(U.[Duration] as varchar), CHARINDEX(':', CAST(U.[Duration] as varchar)) + 7, LEN(CAST(U.[Duration] as varchar))) >= 50) THEN 1 ELSE 0 END as Duration
	,V.ReferStudyViewID
FROM [cta].[tblUserSession] U
JOIN qa.vw_ReferStudyViewReporting V on V.UsersessionID = U.UsersessionID
WHERE 0=0
--Exclude Deleted Sessions
AND U.IsDeleted = 0


GO

/****** Object:  View [qa].[vw_SpecialistReporting]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE VIEW [qa].[vw_SpecialistReporting] as
SELECT 
DISTINCT	 
	 LOWER(S.Email)			AS Email
	,SUBSTRING (LOWER(S.Email), CHARINDEX( '@', LOWER(S.Email)) + 1, LEN(LOWER(S.Email))) AS [Domain]
	,S.FirstName				AS FirstName
	,S.LastName				AS LastName
	,ST.Tag					AS Specialty
	,S.ReferringSpecialistID
	,A.CountryID 
		  
FROM [cta].[tblReferringSpecialist] S 
LEFT JOIN [cta].[tblReferringSpecialistTag] T ON (T.ReferringSpecialistID=S.ReferringSpecialistID AND T.IsDeleted=0)
JOIN [cta].[tblSpecialistTag] ST ON (ST.SpecialistTagID=T.SpecialistTagID)
JOIN [cta].tblReferringSpecialistAddress A on A.ReferringSpecialistID = S.ReferringSpecialistID
WHERE 0=0
--Exclude demo & Non qauction specialists
	AND SUBSTRING (LOWER(S.Email), CHARINDEX( '@', LOWER(S.Email)) + 1, LEN(LOWER(S.Email))) NOT LIKE '%ClinOne%' --Exlcude ClinOne Emails
	AND S.FirstName NOT LIKE '%ClinOne%' --Exclude ClinOne names
	AND ST.IsSpecialty=1 --Include Specialites Only
	AND ST.IsDeleted = 0 --Exclude Deleted Specialties
	AND ST.Tag NOT LIKE '%demo%' --Exclude demo Tags
	AND ST.Tag NOT LIKE '%Clinone%' --exclude ClinOne tags
	AND A.IsPrimary = 1 --Primary Addresses Only
	AND A.IsDeleted = 0 --Exclude Deleted Addresses
	
GO

/****** Object:  View [qa].[vw_PatientRides]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE VIEW [qa].[vw_PatientRides] as
--Created for DS-64 Patient Ride Report
--Get the latest audit record for each ride
WITH LatestRow AS (
	SELECT SitePatientRideId, MAX(RequestDateTimeUtc) AS RequestDateTimeUtc 
	FROM ctc.SitePatientRide
	GROUP BY SitePatientRideId
)
SELECT	
	 A.[SitePatientRideId]
	,A.[SitePatientId]
	,A.[UberStatus]
	,A.[Duration]
	,A.[Distance]
	,A.[TotalFare]
	,A.[CurrencyCode]
	,A.[CreatedDate]
	,D.SponsorName AS Sponsor
	,D.ProtocolNumber AS Protocol
	,D.IsDeleted as StudyArchiveStatus
	,C.SiteName
	,C.SiteNumber
	,C.SiteCity
	,C.SiteZip
	,C.IsDeleted as SiteArchiveStatus
	,D.OrganizationID
	,O.Name as 'Organization'
	,C.SiteStudyID
	
FROM ctc.SitePatientRide A
--Limit to the latest record for each ride from cte above
JOIN LatestRow AA ON (AA.RequestDateTimeUtc=A.RequestDateTimeUTC AND AA.SitePatientRideId=A.SitePatientRideId)
LEFT JOIN ctc.SitePatient B ON (A.SitePatientId=B.SitePatientId)
LEFT JOIN cta.tblSiteStudy C ON (C.SiteGuid=B.SiteGuid AND C.SiteNumber <> '000') --Exclude MySite 
JOIN cta.tblStudy D ON (D.StudyID=C.StudyID)
LEFT JOIN cta.tblOrganization O on (O.OrganizationID = D.OrganizationID )
WHERE 1=1
AND A.IsDeleted = 0 --Exclude Deleted Rides
AND D.SponsorName <> 'ClinOne, Inc.' --Exclude ClinOne Data
GO

/****** Object:  View [qa].[vw_LandingPageActivityReporting]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE VIEW [qa].[vw_LandingPageActivityReporting] as 
--Reporting View for TA Engagement Report
WITH Docs as (
--Details for documents downloaded from the study landing page
SELECT
 V.DocumentVersionID
,V.DocumentID
,D.Name
FROM cta.tbldocumentversion V
JOIN cta.tblDocument D on D.DocumentID = V.DocumentID
WHERE 0=0
)
--CTE To combine the different tables in a reportable format
--Document Downloads, Videos, Optional Link Views, Referral Submits
,Activity as (
--Document Downloads
SELECT
 L.EventID as ID
,'Download Document' as Type
,L.CreatedDateUTC
,L.StudyID
,L.ReferringSpecialistID
,L.UserSessionID
,D.Name as Detail
FROM [dbo].[LandingPageEvents] L
JOIN Docs D on D.DocumentVersionID = L.DocumentVersionID
JOIN qa.vw_SpecialistReporting s on S.ReferringSpecialistID = L.ReferringSpecialistID
JOIN qa.vw_StudyReporting ST on St.StudyID = L.StudyID
WHERE 0=0
AND L.IsDeleted = 0

UNION
--Video Views
SELECT
 L.EventID as ID
,'View Video' as Type
,L.CreatedDateUTC
,L.StudyID
,L.ReferringSpecialistID
,L.UserSessionID
,W.VideoName as Detail
FROM [dbo].[LandingPageEvents] L
JOIN cta.tblWistiaVideo W on W.StudyWistiaProjectID = L.StudyWistiaProjectID
JOIN qa.vw_SpecialistReporting s on S.ReferringSpecialistID = L.ReferringSpecialistID
JOIN qa.vw_StudyReporting ST on St.StudyID = L.StudyID
WHERE 0=0
AND L.IsDeleted = 0

UNION
--Optional Link Views
SELECT
 R.ReferStudyStudyUrlID as ID
,'Optional Link View' as Type
,R.CreatedDateUtc
,R.StudyID
,R.ReferringSpecialistID
,R.UserSessionID
,R.ReferralPath as Detail
FROM cta.tblReferStudyStudyUrl R
JOIN qa.vw_SpecialistReporting s on S.ReferringSpecialistID = R.ReferringSpecialistID
JOIN qa.vw_StudyReporting ST on St.StudyID = R.StudyID
WHERE 0=0
AND r.IsDeleted = 0

UNION 
--Referral Submits
SELECT
 R.ReferStudyReferralSubmitID as ID
,'Referral Submit' as Type
,R.CreatedDateUtc
,R.StudyID
,R.ReferringSpecialistID
,R.UserSessionID
,'N/A' as Detail

FROM cta.[tblReferStudyReferralSubmit ] R
JOIN qa.vw_SpecialistReporting s on S.ReferringSpecialistID = R.ReferringSpecialistID
JOIN qa.vw_StudyReporting ST on St.StudyID = R.StudyID
WHERE 0=0
AND r.IsDeleted = 0
)

--Final Query to join referringspecialistaddress to be able to filter activities by country
SELECT
 A.ID
,A.Type
,A.CreatedDateUTC
,A.StudyID
,A.ReferringSpecialistID
,A.UserSessionID
,A.Detail
,S.CountryID
FROM Activity A
--Join Primary specialist address that is not deleted
JOIN cta.tblReferringSpecialistAddress S on S.ReferringSpecialistID = A.ReferringSpecialistID
WHERE 0=0
AND S.IsPrimary = 1
AND S.IsDeleted = 0
GO

/****** Object:  View [qa].[vw_BotActivityLogic]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE VIEW [qa].[vw_BotActivityLogic] as 
WITH ClickDetailDistinct as (
SELECT
DISTINCT
 A.SentEmailID
,A.Url
--Categorizing Clicks based on Bill's supplied URLs
--NonStudyClicks
,CASE WHEN
	A.Url IN (
 'https://clinone.com'
,'https://www.clinone.com' 
,'https://clinone.com/privacy' 
,'https://www.linkedin.com/company/clinone' 
) OR A.Url LIKE '%Unsubscribe%' THEN 1
ELSE 0
	END AS 'NonStudyURLsClicked'
--Study Clicks (not used, just for discovery purposes)
,CASE WHEN A.Url LIKE '%Study%' THEN 1 ELSE 0 END AS 'StudyURLsCLicked'

FROM qa.tblSentEmailClickDetail A
--Try to only look at nonstudy links clicked the same day as the email was sent
JOIN qa.EmailReportingTA B ON B.SentEmailID=A.SentEmailID AND CAST(A.CreatedDateUtc as date) = CAST(B.CreatedDate as date)
WHERE 0=0
AND A.Isdeleted = 0
--Limiting to last 400 days since TA Engagment is for the past year currently
AND CAST(B.CreatedDate as date) >= DATEADD( DAY , -400, GETDATE() )
--Test case
--AND A.SentEmailID = 6590631
)
,EmailClickTimings as (
--Only look at nonstudyurl clicks
--get click timings for first and last nonstudy url click for each email that occurred on the same day as the email was sent
SELECT
 A.SentEmailID
,B.Email
,B.CreatedDate
,MIN(A.CreatedDateUTC) as FirstClick
,MAX(A.CreatedDateUTC) as LastClick
,DATEDIFF(SECOND, MIN(B.CreatedDate),MIN(A.CreatedDateUTC) ) as DurationBetweenEmailSentandFirstClickSeconds
,DATEDIFF(SECOND, MIN(A.CreatedDateUTC),MAX(A.CreatedDateUTC) ) as DurationBetweenFirstClickLastClickSeconds

FROM qa.tblSentEmailClickDetail A
JOIN qa.EmailReportingTA B ON B.SentEmailID = A.SentEmailID AND CAST(A.CreatedDateUtc as date) = CAST(B.CreatedDate as date)
WHERE 0=0
AND A.Isdeleted = 0
--Limiting to last 400 days since TA Engagment is for the past year currently
AND CAST(B.CreatedDate as date) >= DATEADD( DAY , -400, GETDATE() )
--Test case
--AND B.SentEmailID = 6590631
AND (A.Url IN (
 'https://clinone.com'
,'https://www.clinone.com' 
,'https://clinone.com/privacy' 
,'https://www.linkedin.com/company/clinone' 
) OR A.Url LIKE '%Unsubscribe%' )

GROUP BY A.SentEmailID,B.Email,B.CreatedDate
)
,AggregateClicks as (
--Aggregate links per click category
SELECT
  D.SentEmailID
,SUM( D.NonStudyURLsClicked ) as NonStudyURLsClicked
-- >=5 not study links means potential bot activity
-- call this possible bot
--if it is in the same session then it is likely bot
,CASE WHEN SUM(D.NonStudyURLsClicked ) >= 5 THEN 1 ELSE 0 END AS PossibleBot
,SUM( D.StudyURLsClicked ) as StudyURLsClicked

FROM ClickDetailDistinct D 
WHERE 0=0
GROUP BY D.SentEmailID
)

----This CTE for identifying if a specialist has every been emailed for a study, if they haven't then it is likely bot activity
--,SentEmailsPerStudyPerEmail as (
-- SELECT
--    E.Email
--  ,T.StudyID
--  ,COUNT(E.SentEmailID) as SentEmails
--  FROM qa.EmailReportingTA E 
--  JOIN qa.EmailStudyBridge T on T.SentEmailID = E.SentEmailID 
--  WHERE 0=0
--  GROUP BY 
--   E.Email
--  ,T.StudyID
--)
SELECT
 A.SentEmailID
,T.CreatedDate as EmailSentDateTime
,T.Email
,A.NonStudyURLsClicked
,A.StudyURLsClicked
,A.PossibleBot -- See notes above
,T.FirstClick
,T.LastClick 
,T.DurationBetweenEmailSentandFirstClickSeconds
,T.DurationBetweenFirstClickLastClickSeconds
,V.ReferStudyViewID
,V.CreatedDateUtc as 'Study View Created'
,V.StudyID
,V.UserSessionID
,U.CreatedDateUtc as SessionDateTime
,E.SentEmails
--If a session or view happened between the first and last nonstudy url click of possible bot activity on email then it is likely a bot view
--adding logic for if a specialist was never sent an email for a study then it is likely a bot (sentemails is null)
,CASE WHEN A.PossibleBot = 1 AND V.CreatedDateUtc BETWEEN T.FirstClick and T.LastClick THEN 1 WHEN E.SentEmails IS NULL THEN 1 ELSE 0 END AS 'LikelyBot'
FROM AggregateClicks A 
JOIN EmailClickTimings T on T.SentEmailID = A.SentEmailID
--Join to study views that ocurred on the same day as a sent email to the same referring specialist
JOIN cta.tblReferringSpecialist S on S.Email = T.Email
JOIN cta.tblReferStudyView V on V.ReferringSpecialistID = S.ReferringSpecialistID AND CAST(V.CreatedDateUtc as date) = CAST(T.FirstClick as DATE) 
JOIN cta.TblUserSession U on U.UserSessionID = V.UserSessionID
--Count if a specialist has received an email for the study they viewed
LEFT JOIN qa.SentEmailsPerStudyPerEmail E on E.Email = T.Email AND E.StudyID = V.StudyID
WHERE 0=0
GO


/****** Object:  View [qa].[vw_EmailBridgeTable]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--Created at: 2022-06-08 13:57:19.990
--SQL User: vgoyal@clinone.com
--Description: Bridge Table For Email Study RelationShips
--Have to parse study and sitestudy ids from json column
CREATE VIEW [qa].[vw_EmailBridgeTable] as 
--limit to required columns for extracting Json
WITH Emails as (
SELECT 
	   E.[SentEmailID]
      ,E.[MetaData]
FROM [cta].[tblSentEmail] E
WHERE 0=0
--Research newsletter & CustomResearchNewsletters email types
  AND SentEmailTypeID IN (23,47)
--metadata needs to be not null for cross apply below to work
  AND MetaData IS NOT NULL
  
  )

--OpenJson function to extract to column and rows for each study/sitestudy
SELECT
 [SentEmailID]
,List.StudyID
,List.SiteStudyID
FROM Emails T
CROSS APPLY OPENJSON( [Metadata],'$.ReferralStudyIDs' )
WITH (
		StudyID int '$.StudyID',
		SiteStudyId int '$.SiteStudyID'
) as List
--limit to required studies for TA Engagment reporting
JOIN [qa].[vw_StudyReporting] STU ON STU.StudyID=List.StudyID
WHERE 0=0
--extra check to ensure there is json in the metadata column
AND ISJSON(Metadata) > 0

GO

/****** Object:  View [qa].[vw_StudyReporting]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE VIEW [qa].[vw_StudyReporting] as 
--Used for Study Reporting for DS-43
SELECT
 S.StudyID
,S.SponsorName
,S.ProtocolNumber
,CAST(S.CreatedDate as DATE) as CreatedDate
,S.IsDeleted
,S.StudyNickname
,S.OrganizationID
,S.MDReferralVersionID
,S.IsMDReferralEnabledFinal
,S.StudyClientTypeID
FROM cta.tblstudy S
WHERE 0=0
--Exclude Demos
AND S.IsDemo = 0
--Exclude ClinOne Sponsor names
AND S.SponsorName NOT LIKE '%ClinOne%'
--Premium Studies Only
AND S.StudyClientTypeID = 1
--Exclude Test Sponsors
AND S.sponsorname NOT LIKE '%test%'
--Exlcude ClinOne Organization ID but allow null Organization IDs since it's an optional field
AND (S.OrganizationID NOT IN( 38) OR S.OrganizationID IS NULL)
GO

/****** Object:  View [qa].[vw_SiteStudyReporting]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE VIEW [qa].[vw_SiteStudyReporting] as 
SELECT
 SS.SiteStudyID
,SS.StudyID
,SS.SiteNumber
,SS.SiteName
,SS.SiteAddressLine1
,SS.SiteAddressLine2
,SS.SiteCity
,SS.SiteGoverningDistrict
,SS.SiteZip 
,SS.SiteCountryID 
,SS.CreatedBy 
,SS.IsDeleted
,SS.IsConnectEnabled
,SS.IsSoeEnabled
,SS.TimeZoneID
,SS.IsAeEnabled
,SS.MaxReferralDistance
,SS.IsMDReferralEnabledFinal as IsMDReferralEnabled
--,SS.GeoLocation
,SS.ReferringSpecialistCount
FROM cta.tblSiteStudy SS
JOIN [qa].[vw_StudyReporting] S ON S.StudyID=SS.StudyID
WHERE 0=0
--SiteStudyBizRules
--AND SS.IsDeleted = 0
AND SS.SiteNumber <> '000'
GO

/****** Object:  View [qa].[vw_OrganizationReporting]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE VIEW [qa].[vw_OrganizationReporting] as 
--Organization Reporting for DS-43
SELECT
 OrganizationID
,Name
FROM cta.tblOrganization
WHERE 0=0
--Exclude ClinOne
AND OrganizationID <> 38
--Exclude Deleted Organizations
AND IsDeleted = 0
GO


/****** Object:  View [qa].[vw_TASiteReporting]    Script Date: 10/19/2023 10:05:04 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--Created at: 2022-07-06 13:58:44.594
--SQL User: vgoyal@clinone.com
--Description: TA Site Information DS-54

CREATE VIEW [qa].[vw_TASiteReporting] as

WITH ReferralContact as (
--CTE for referral contacts per Site
SELECT
 SiteStudyID
,COUNT(DISTINCT CTAUserSiteStudyID ) as ReferralContacts
FROM cta.tblCTAUserSiteStudy
WHERE 0=0
AND IsDeleted = 0
AND IsReferralContact = 1
GROUP BY 
SiteStudyID
)
SELECT
 O.Name as 'Organization Name'
,O.OrganizationID
,ST.SponsorName as 'Sponsor Name'
,ST.ProtocolNumber
,ST.StudyID
,A.StudyAdminStatus
,S.SiteNumber
,S.SiteStudyID
,S.SiteName
,S.SiteAddressLine1
,S.SiteAddressLine2
,S.SiteCity
,S.SiteGoverningDistrict
,S.SiteZip
--Combine Address columns
,S.SiteAddressLine1 + ' ' + COALESCE(S.SiteAddressLine2 , '' ) + ' ' + S.SiteCity + ', ' + COALESCE(S.SiteGoverningDistrict, '') + ' ' + COALESCE(S.SiteZip,'') as Detail
,C.NiceName as 'Country'
,C.CountryID
,S.PrincipalInvestigatorName
,S.IsMDReferralEnabledFinal as IsMDReferralEnabled
,S.MaxReferralDistance
--Joined Referral Contacts from CTE
,CASE WHEN R.ReferralContacts IS NOT NULL THEN 1 ELSE 0 END AS 'At Least one Referral Contact'
,R.ReferralContacts
,S.ReferringSpecialistCount
,S.IsCommunityEnabledFinal as IsCommunityEnabled
,S.IsCriteriaEnabledFinal as IsCriteriaEnabled
,S.IsResourcesEnabledFinal as IsResourcesEnabled
,S.IsStudyPersonnelEnabledFinal as IsStudyPersonnelEnabled
,S.IsVendorsEnabledFinal as IsVendorsEnabled
,S.IsCreateSubjectThroughUserInterfaceEnabled
FROM cta.tblSiteStudy S
JOIN cta.lk_country C on C.CountryID = S.SiteCountryID
JOIN cta.tblStudy ST on ST.StudyID = S.StudyID
JOIN cta.tblOrganization O on O.OrganizationID = ST.OrganizationID
JOIN cta.lk_StudyAdminStatus A on A.StudyAdminStatusID = ST.StudyAdminStatusID
LEFT JOIN ReferralContact R on R.SiteStudyID = S.SiteStudyID
WHERE 0=0
--Exclude Deleted/Demo Records and non qauction Data
AND S.IsDeleted = 0
AND O.IsDeleted = 0
AND ST.IsDeleted = 0
AND ST.IsDemo = 0
AND S.SiteNumber <> '000'
AND S.SiteName <> '%My Site%'
AND ST.SponsorName <> 'ClinOne'
AND O.OrganizationID <> 38
GO

/****** Object:  View [qa].[vw_SubjectStatusReporting]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--most current status per subject based on iscurrent
CREATE VIEW [qa].[vw_SubjectStatusReporting] as 

SELECT DISTINCT
       S.StudySoeSubjectStatus 
	  ,SSS.IsDeleted as SubjectArchived
	  ,U.UserID
	  	  
  FROM [cta].[tblStudySoeSubjectStatusReason] R
  JOIN [cta].[lk_StudySoeSubjectStatusReasonType] T on T.StudySoeSubjectStatusReasonTypeID = R.StudySoeSubjectStatusReasonTypeID
  JOIN [cta].[lk_StudySoeSubjectStatus] S on S.StudySoeSubjectStatusID = T.StudySoeSubjectStatusTypeID
  JOIN [cta].tblStudySoeSubject SSS on SSS.StudySoeSubjectID = R.StudySoeSubjectID 
  JOIN [cta].tblSiteStudy SS on SS.SiteStudyID = SSS.SiteStudyID AND SS.SiteNumber <> '000' --Exclude MySite
  JOIN [cta].tblstudy D ON (D.StudyID=SS.StudyID)
  JOIN [ctc].SitePatient P on P.CtaStudySoeSubjectGuid = SSS.StudySoeSubjectGuid --This limiting join to about 2k subjects
  JOIN [ctc].[User] U on U.UserID = P.UserID
  WHERE 0=0
  --Current Subject Status Reason
  AND R.IsCurrent = 1
  --Exlcude Deleted Subject Status Reasons
  AND R.IsDeleted = 0
  --Exclude Demo Users
  AND u.IsDemo = 0
  --Exclude ClinOne SponsorNames
  AND D.SponsorName NOT LIKE '%ClinOne%' 
  --Exlcude Test sponsor
  AND D.sponsorname NOT LIKE '%test%' 
  --Exclude ClinOne Organization or allow null OrganizationIDs
  AND (D.OrganizationID NOT IN( 38) OR D.OrganizationID IS NULL)
  --Exclude Demo Studies
  AND D.IsDemo = 0
  

GO

/****** Object:  View [qa].[vw_LandingPageActivities]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--Created at: 12\/18-2023  9:10:07 AM

--SQL User: vgoyal@clinone.com
--Description: Add in Details about landing page assets
--Stored in view for potential maintenance
--qa.EtlLandingPageEvents stored proc inserts this data to table

CREATE VIEW [qa].[vw_LandingPageActivities] as
--Only include columns with event detail
--Parses Json Column
SELECT
 E.EventID
,T.EventType
,E.CreatedDateUTC
,E.CreatedBy
,E.IsDeleted
,List.StudyID
,List.ReferringSpecialistID
,List.DocumentVersionID
,List.UserSessionID
,List.ViewedPercentage
,List.StudyWistiaProjectID
FROM cta.tblevent E
JOIN cta.lk_EventType T on T.EventTypeID = E.EventTypeID
--Json function to parse data
CROSS APPLY OPENJSON( E.EventData )
WITH (
		StudyID int '$.StudyID',
		ReferringSpecialistID int '$.ReferringSpecialistID',
		DocumentVersionID int '$.DocumentVersionID',
		UserSessionID int '$.UserSessionID',
		ViewedPercentage decimal(18,2) '$.ViewedPercentage',
		StudyWistiaProjectID int '$.StudyWistiaProjectID'
) as List
GO

/****** Object:  View [qa].[vw_Country]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--Created at: 15/12/2023 17:11:07
--SQL User: vgoyal@clinone.com
--Description: Country Reporting View
CREATE VIEW [qa].[vw_Country] as
SELECT
	 [CountryID]
    ,[ISO]
	,[NiceName]
FROM [cta].[lk_Country]
GO
/****** Object:  View [qa].[vw_EmailsReporting]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [qa].[vw_EmailsReporting] as 
SELECT [SentEmailID]
      ,[Email]
      ,CAST([CreatedDate] as DATE) as [CreatedDate]
      ,[OpenedCount]
      ,[ClickedCount]
      
FROM [qa].[EmailReportingTA]
WHERE 0=0
GO
/****** Object:  Table [cta].[tblSentEmail]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE EXTERNAL TABLE [cta].[tblSentEmail]
(
	[SentEmailID] [int] NOT NULL,
	[SentEmailTypeID] [int] NOT NULL,
	[ToEmailAddress] [nvarchar](256) NOT NULL,
	[FromEmailAddress] [nvarchar](256) NOT NULL,
	[WasSuccessful] [bit] NOT NULL,
	[ToCTAUserID] [int] NULL,
	[EmailItemID] [int] NULL,
	[CreatedDate] [datetime] NOT NULL,
	[CreatedBy] [nvarchar](256) NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[ModifiedDate] [datetime] NOT NULL,
	[ModifiedBy] [nvarchar](256) NOT NULL,
	[SendGridMessageID] [nvarchar](250) NULL,
	[OpenedCount] [int] NULL,
	[ClickedCount] [int] NULL,
	[IsBounced] [bit] NULL,
	[IsMarkedSpam] [bit] NULL,
	[IsUnsubscribed] [bit] NULL,
	[ForumPostID] [int] NULL,
	[InitialOpenedDateUtc] [date] NULL,
	[MetaData] [nvarchar](max) NULL,
	[Body] [nvarchar](max) NULL,
	[Subject] [nvarchar](max) NULL,
	[UniqueIpAddressCount] [int] NULL
)
WITH (DATA_SOURCE = [DbCtaDataSource],SCHEMA_NAME = N'dbo',OBJECT_NAME = N'tblSentEmail ')
GO

/****** Object:  StoredProcedure [qa].[ETLBotActivityLogic]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [qa].[ETLBotActivityLogic]
--Load bot activity logic form view to table to improve performance
--DS-55
AS
BEGIN

--CurrentDatetime used for logging purposes
DECLARE @ST as DATETIME = GETDATE()

--Truncate and full load table
TRUNCATE TABLE [qa].[BotActivityLogic];

--Insert to table
INSERT INTO qa.BotActivityLogic
SELECT [SentEmailID]
      ,[EmailSentDateTime]
      ,[Email]
      ,[NonStudyURLsClicked]
      ,[StudyURLsClicked]
      ,[PossibleBot]
      ,[FirstClick]
      ,[LastClick]
      ,[DurationBetweenEmailSentandFirstClickSeconds]
      ,[DurationBetweenFirstClickLastClickSeconds]
      ,[ReferStudyViewID]
      ,[Study View Created]
      ,[StudyID]
      ,[UserSessionID]
      ,[SessionDateTime]
	  ,[SentEmails]
      ,[LikelyBot]
  FROM [qa].[vw_BotActivityLogic];

--insert rowcount to log table  
INSERT INTO [qa].[StoredProcLog]
SELECT 'qa.ETLBotActivityLogic' as StoredProcName, @@ROWCOUNT as [Rows], @ST as StartTime, GETDATE() as EndTime
END
GO


/****** Object:  StoredProcedure [qa].[ETLEmailReportingClickDetailIncremental]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [qa].[ETLEmailReportingClickDetailIncremental]

--Incremental Load of Email Clicks for Bot Activity
--Inserts to analytics db from external table source from ctc
--Runs daily via scheduled Power Automate flow
AS
BEGIN
--CurrentDatetime used for logging purposes
DECLARE @ST as DATETIME = GETDATE()
--Select the max modified datetime from the local table 
--to insert or update every record from the external table occuring after that modified datetime
DECLARE @MostrecentClickModifiedDateTime  Datetime
SET @MostrecentClickModifiedDateTime = (SELECT MAX(ModifiedDateUtc) as MostrecentsentemailDateTime FROM [qa].[tblSentEmailClickDetail]);
WITH SOURCE AS (
SELECT --top 10
	   C.[SentEmailClickDetailID]
      ,C.[SentEmailID]
      ,C.[CreatedDateUtc]
      ,C.[IsDeleted]
      ,C.[Url]
      ,C.[ModifiedDateUtc]
      ,C.[ModifiedBy]
      ,C.[CreatedBy]
FROM [cta].tblSentEmailClickDetail C 
JOIN [cta].[tblSentEmail] E on E.SentEmailID = C.SentEmailID
WHERE 0=0
--Only get recently modified/new records
AND E.ModifiedDate > @MostrecentClickModifiedDateTime
--Research newsletter & CustomResearchNewsletters
	AND SentEmailTypeID IN (23,47)
	AND E.ToEmailAddress NOT LIKE '%Clinone%'
	AND E.ToEmailAddress NOT LIKE '%demo%'
)
MERGE [qa].[TblSentEmailClickDetail] AS TARGET
USING SOURCE
	ON TARGET.[SentEmailClickDetailID] = SOURCE.[SentEmailClickDetailID]
WHEN MATCHED 
	AND SOURCE.ModifiedDateUTC <> TARGET.ModifiedDateUTC
THEN UPDATE SET
	 TARGET.[SentEmailClickDetailID] = SOURCE.[SentEmailClickDetailID]
	,TARGET.[SentEmailID] = SOURCE.[SentEmailID]
	,TARGET.[CreatedDateUtc] = SOURCE.[CreatedDateUtc]
	,TARGET.[IsDeleted] = SOURCE.[IsDeleted]
	,TARGET.[Url] = SOURCE.[Url]
	,TARGET.[ModifiedDateUtc] = SOURCE.[ModifiedDateUtc]
	,TARGET.[ModifiedBy] = SOURCE.[ModifiedBy]
	,TARGET.[CreatedBy] = SOURCE.[CreatedBy]
WHEN NOT MATCHED BY TARGET
THEN INSERT (
		 [SentEmailClickDetailID]
		,[SentEmailID]
		,[CreatedDateUtc]
		,[IsDeleted]
		,[Url]
		,[ModifiedDateUtc]
		,[ModifiedBy]
		,[CreatedBy]
		   )
	VALUES (
	
	 SOURCE.[SentEmailClickDetailID]
	,SOURCE.[SentEmailID]
	,SOURCE.[CreatedDateUtc]
	,SOURCE.[IsDeleted]
	,SOURCE.[Url]
	,SOURCE.[ModifiedDateUtc]
	,SOURCE.[ModifiedBy]
	,SOURCE.[CreatedBy] );  
INSERT INTO [qa].[StoredProcLog]
SELECT 'qa.ETLEmailReportingClickDetailIncremental' as StoredProcName, @@ROWCOUNT as [Rows], @ST as StartTime, GETDATE() as EndTime
END
GO


/****** Object:  StoredProcedure [qa].[ETLEmailReportingTA]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [qa].[ETLEmailReportingTA]
--Full load of Email reporting for TA
--Inserts to analytics db from external table source from ctc
AS
BEGIN
DECLARE @ST as DATETIME = GETDATE()
TRUNCATE TABLE [qa].[EmailReportingTA];
WITH B as (SELECT DISTINCT SentemailID FROM qa.vw_EmailBridgeTable)
,DistinctSpecialistEmails as (
SELECT 
DISTINCT	 
	 LOWER(S.Email)			AS Email		  
FROM [cta].[tblReferringSpecialist] S 
LEFT JOIN [cta].[tblReferringSpecialistTag] T ON (T.ReferringSpecialistID=S.ReferringSpecialistID AND T.IsDeleted=0)
JOIN [cta].[tblSpecialistTag] ST ON (ST.SpecialistTagID=T.SpecialistTagID)
JOIN [cta].tblReferringSpecialistAddress A on A.ReferringSpecialistID = S.ReferringSpecialistID
WHERE 0=0
--Exclude demo & Non qauction specialists
	AND SUBSTRING (LOWER(S.Email), CHARINDEX( '@', LOWER(S.Email)) + 1, LEN(LOWER(S.Email))) NOT LIKE '%ClinOne%' --Exlcude ClinOne Emails
	AND S.FirstName NOT LIKE '%ClinOne%' --Exclude ClinOne names
	AND ST.IsSpecialty=1 --Include Specialites Only
	AND ST.IsDeleted = 0 --Exclude Deleted Specialties
	AND ST.Tag NOT LIKE '%demo%' --Exclude demo Tags
	AND ST.Tag NOT LIKE '%Clinone%' --exclude ClinOne tags
	AND A.IsPrimary = 1 --Primary Addresses Only
	AND A.IsDeleted = 0 --Exclude Deleted Addresses
	
)

INSERT INTO [qa].[EmailReportingTA]
           ([SentEmailID]
		   ,[Email]
           ,[SentEmailTypeID]
           ,[WasSuccessful]
           ,[CreatedDate]
           ,[IsDeleted]
           ,[OpenedCount]
           ,[ClickedCount]
           ,[IsBounced]
           ,[IsMarkedSpam]
           ,[IsUnsubscribed]
		   ,ModifiedDate)
SELECT 
	   E.[SentEmailID]
	  ,S.[Email]
	  ,E.[SentEmailTypeID]
      ,E.[WasSuccessful]
      ,E.[CreatedDate]
      ,E.[IsDeleted]
      ,E.[OpenedCount]
      ,E.[ClickedCount]
      ,E.[IsBounced]
      ,E.[IsMarkedSpam]
      ,E.[IsUnsubscribed]
	  ,E.ModifiedDate
FROM [cta].[tblSentEmail] E
JOIN DistinctSpecialistEmails S on S.Email = E.ToEmailAddress
JOIN  B on B.SentEmailID = E.SentEmailID
WHERE 0=0
--Research newsletter & CustomResearchNewsletters
  AND SentEmailTypeID IN (23,47)
  --Last 400 Days
  --AND CAST(E.CreatedDate as date) >= CAST(DATEADD( DAY , -400, GETDATE() ) as date)
  
INSERT INTO [qa].[StoredProcLog]
SELECT 'qa.EmailReportingTA' as StoredProcName, @@ROWCOUNT as [Rows], @ST as StartTime, GETDATE() as EndTime
END
GO
/****** Object:  StoredProcedure [qa].[ETLEmailReportingTAIncremental]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [qa].[ETLEmailReportingTAIncremental]
--Incremental Load of Email dataset for Trial Awareness Engagement
--Inserts to analytics db from external table source from ctc
--Runs daily via scheduled Power Automate flow
AS
BEGIN
--CurrentDatetime used for logging purposes
DECLARE @ST as DATETIME = GETDATE()
--Select the max modified datetime from the local table 
--to insert or update every record from the external table occuring after that modified datetime
DECLARE @MostrecentsentemailDateTime  Datetime
SET @MostrecentsentemailDateTime = (SELECT MAX(ModifiedDate) as MostrecentsentemailDateTime FROM [qa].[EmailReportingTA]);
WITH DistinctSpecialistEmails as (
SELECT 
DISTINCT	 
	 LOWER(S.Email)			AS Email		  
FROM [cta].[tblReferringSpecialist] S 
LEFT JOIN [cta].[tblReferringSpecialistTag] T ON (T.ReferringSpecialistID=S.ReferringSpecialistID AND T.IsDeleted=0)
JOIN [cta].[tblSpecialistTag] ST ON (ST.SpecialistTagID=T.SpecialistTagID)
JOIN [cta].tblReferringSpecialistAddress A on A.ReferringSpecialistID = S.ReferringSpecialistID
WHERE 0=0
--Exclude demo & Non qauction specialists
	AND SUBSTRING (LOWER(S.Email), CHARINDEX( '@', LOWER(S.Email)) + 1, LEN(LOWER(S.Email))) NOT LIKE '%ClinOne%' --Exlcude ClinOne Emails
	AND S.FirstName NOT LIKE '%ClinOne%' --Exclude ClinOne names
	AND ST.IsSpecialty=1 --Include Specialites Only
	AND ST.IsDeleted = 0 --Exclude Deleted Specialties
	AND ST.Tag NOT LIKE '%demo%' --Exclude demo Tags
	AND ST.Tag NOT LIKE '%Clinone%' --exclude ClinOne tags
	AND A.IsPrimary = 1 --Primary Addresses Only
	AND A.IsDeleted = 0 --Exclude Deleted Addresses	
)
,SOURCE AS (
SELECT 
	   E.[SentEmailID]
	  ,S.[Email]
      ,E.[WasSuccessful]
      ,E.[CreatedDate]
      ,E.[IsDeleted]
      ,E.[OpenedCount]
      ,E.[ClickedCount]
      ,E.[IsBounced]
      ,E.[IsMarkedSpam]
      ,E.[IsUnsubscribed]
	  ,E.ModifiedDate
FROM [cta].[tblSentEmail] E
JOIN DistinctSpecialistEmails S on S.Email = E.ToEmailAddress
WHERE 0=0
--Only get recently modified/new records
	AND E.ModifiedDate > @MostrecentsentemailDateTime
--Research newsletter & CustomResearchNewsletters
	AND SentEmailTypeID IN (23,47)
	AND E.ToEmailAddress NOT LIKE '%Clinone%'
	AND E.ToEmailAddress NOT LIKE '%demo%'
)
MERGE [qa].[EmailReportingTA] AS TARGET

USING SOURCE
	ON TARGET.SentEmailID = SOURCE.SentEmailID
WHEN MATCHED 
	AND SOURCE.ModifiedDate <> TARGET.ModifiedDate
THEN UPDATE SET
	 TARGET.Email = SOURCE.Email
	,TARGET.[WasSuccessful] = SOURCE.[WasSuccessful]
	,TARGET.[CreatedDate] = SOURCE.[CreatedDate]
	,TARGET.[IsDeleted] = SOURCE.[IsDeleted]
	,TARGET.[OpenedCount] = SOURCE.[OpenedCount]
	,TARGET.[ClickedCount] = SOURCE.[ClickedCount]
	,TARGET.[IsBounced] = SOURCE.[IsBounced]
	,TARGET.[IsMarkedSpam] = SOURCE.[IsMarkedSpam]
	,TARGET.[IsUnsubscribed] = SOURCE.[IsUnsubscribed]
	,TARGET.ModifiedDate = SOURCE.ModifiedDate
WHEN NOT MATCHED BY TARGET
THEN INSERT (
            [SentEmailID]
           ,[Email]
           ,[WasSuccessful]
           ,[CreatedDate]
           ,[IsDeleted]
           ,[OpenedCount]
           ,[ClickedCount]
           ,[IsBounced]
           ,[IsMarkedSpam]
           ,[IsUnsubscribed]
		   ,ModifiedDate
		   )
	VALUES (
	SOURCE.[SentEmailID]
           ,SOURCE.[Email]
           ,SOURCE.[WasSuccessful]
           ,SOURCE.[CreatedDate]
           ,SOURCE.[IsDeleted]
           ,SOURCE.[OpenedCount]
           ,SOURCE.[ClickedCount]
           ,SOURCE.[IsBounced]
           ,SOURCE.[IsMarkedSpam]
           ,SOURCE.[IsUnsubscribed]
		   ,SOURCE.ModifiedDate );

 --Create Record in Log Table with start time, end time, and rowcount
INSERT INTO [qa].[StoredProcLog]
SELECT 'qa.EmailReportingTAIncremental' as StoredProcName, @@ROWCOUNT as [Rows], @ST as StartTime, GETDATE() as EndTime
END
GO
/****** Object:  StoredProcedure [qa].[ETLEmailStudyBridgeIncremental]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [qa].[ETLEmailStudyBridgeIncremental]

--Incremental Load of Email Study bridge View to Table
--Inserts to analytics db from external table source from ctc
--Runs daily via scheduled Power Automate flow
AS
BEGIN
--CurrentDatetime used for logging purposes
DECLARE @ST as DATETIME = GETDATE()

--Select the max SentEmailID from EmailStudyBridge
--to insert or update every record from the Bridge Table based on sentemailid
DECLARE @MostrecentsentemailID  INT
SET @MostrecentsentemailID = (SELECT MAX(SentEmailID) as MostrecentsentemailID FROM [qa].[EmailStudyBridge]);
WITH SOURCE AS (
SELECT
 [SentEmailID]
,[StudyID]
--Custom Newsletters do not have a SiteStudyID, replace the null values with -1
,ISNULL([SiteStudyID], -1 ) as [SiteStudyID]
FROM [qa].[vw_EmailBridgeTable]
WHERE 0=0
--Only load emails greater than the most recent one in the table
AND SentEmailID > @MostrecentsentemailID
)
MERGE [qa].[EmailStudyBridge] AS TARGET
USING SOURCE
	ON TARGET.SentEmailID = SOURCE.SentEmailID
WHEN MATCHED 
	AND SOURCE.[StudyID] <> TARGET.[StudyID]
THEN UPDATE SET
	 TARGET.[StudyID] = SOURCE.[StudyID]
	,TARGET.[SiteStudyID] = SOURCE.[SiteStudyID]
	
WHEN NOT MATCHED BY TARGET
THEN INSERT (
            [SentEmailID]
		   ,[StudyID]
	      ,[SiteStudyID]
		   )
	VALUES (
	SOURCE.[SentEmailID]
           ,SOURCE.[StudyID]
           ,SOURCE.[SiteStudyID] );
 --Create Record in Log Table with start time, end time, and rowcount
INSERT INTO [qa].[StoredProcLog]
SELECT 'qa.EmailBridgeTableIncremental' as StoredProcName, @@ROWCOUNT as [Rows], @ST as StartTime, GETDATE() as EndTime
END
GO

/****** Object:  StoredProcedure [qa].[ETLLandingPageEvents]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [qa].[ETLLandingPageEvents]
--Load data from view to table for performance and format for reporting
AS
BEGIN
--use for ETL logging
DECLARE @ST as DATETIME = GETDATE()
--truncate records and do full load
TRUNCATE TABLE [dbo].[LandingPageEvents];
INSERT INTO [dbo].[LandingPageEvents]
SELECT 
	 [EventID]
	,[EventType]
	,[CreatedDateUTC]
	,[CreatedBy]
	,[IsDeleted]
	,[StudyID]
	,[ReferringSpecialistID]
	,[DocumentVersionID]
	,[UserSessionID]
	,[ViewedPercentage]
	,[StudyWistiaProjectID]
FROM [qa].[vw_LandingPageActivities]
--Create record with rowcount and start and end time
INSERT INTO [qa].[StoredProcLog]
SELECT 'qa.ETLLandingPageEvents' as StoredProcName, @@ROWCOUNT as [Rows], @ST as StartTime, GETDATE() as EndTime
END
GO

/****** Object:  StoredProcedure [qa].[ETLSentEmailsPerStudyPerEmail]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [qa].[ETLSentEmailsPerStudyPerEmail]
--Load data from view to table for performance and format for reporting
AS
BEGIN
--use for ETL logging
DECLARE @ST as DATETIME = GETDATE()
--truncate records and do full load
TRUNCATE TABLE [qa].[SentEmailsPerStudyPerEmail];

INSERT INTO [qa].[SentEmailsPerStudyPerEmail]
--Insert all TA Emails sent to each email address per study
SELECT
	 E.Email
	,T.StudyID
	,COUNT(E.SentEmailID) as SentEmails
FROM qa.EmailReportingTA E 
JOIN qa.EmailStudyBridge T on T.SentEmailID = E.SentEmailID 
WHERE 0=0
GROUP BY 
	 E.Email
	,T.StudyID

--Create record with rowcount and start and end time
INSERT INTO [qa].[StoredProcLog]
SELECT 'qa.ETLSentEmailsPerStudyPerEmail' as StoredProcName, @@ROWCOUNT as [Rows], @ST as StartTime, GETDATE() as EndTime
END
GO

/****** Object:  StoredProcedure [qa].[NEWEmailAggregate]    Script Date: 12\/18-2023  9:10:07 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [qa].[NEWEmailAggregate]
--Load data from view to table for performance and format for reporting
AS
BEGIN
--use for ETL logging
DECLARE @ST as DATETIME = GETDATE()
--truncate records and do full load
SELECT
	EB.SentEmailID,
    ER.Email,
    ER.CreatedDate,
    COUNT(CASE WHEN ER.OpenedCount > 0 THEN 1 END) AS [CountOpened],
    SUM(ER.ClickedCount) AS [CountClicked],
    EB.StudyID,
    EB.SiteStudyID
  FROM
    [qa].[vw_EmailsReporting] ER
    LEFT JOIN [qa].[vw_EmailBridgeTable] EB ON ER.SentEmailID = EB.SentEmailID
  --WHERE
    --ER.OpenedCount >= 0 AND ER.ClickedCount >= 0
  GROUP BY
    ER.Email,
    ER.CreatedDate,
    EB.StudyID,
    EB.SiteStudyID,
	EB.SentEmailID;
--Create record with rowcount and start and end time
SELECT 'qa.NEWEmailAggregate' as StoredProcName, @@ROWCOUNT as [Rows], @ST as StartTime, GETDATE() as EndTime
END
GO