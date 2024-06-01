CREATE SCHEMA [uat] AUTHORIZATION [dbo];

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql += N' ALTER SCHEMA uat TRANSFER ' 
          + QUOTENAME(s.name) + '.' + QUOTENAME(o.name) + ';'
FROM sys.objects AS o
INNER JOIN sys.schemas AS s
ON o.[schema_id] = s.[schema_id]
WHERE s.name = N'TEST'; 

EXEC sp_executesql @sql;

DROP SCHEMA [TEST];
