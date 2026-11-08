#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import <string.h>

static NSString *const TargetGroup = @"VJGTV94XY8.com.taobao.taobao4iphone";

static NSDictionary *CountTable(sqlite3 *database, NSString *table, BOOL classifyServices)
{
    NSString *category = classifyServices ? @"CASE "
        "WHEN lower(CAST(svce AS TEXT)) LIKE '%utdid%' OR lower(CAST(svce AS TEXT)) LIKE '%umid%' "
        "OR lower(CAST(svce AS TEXT)) LIKE '%device%' OR lower(CAST(svce AS TEXT)) LIKE '%uuid%' THEN 'identity_related_name' "
        "WHEN lower(CAST(svce AS TEXT)) LIKE '%login%' OR lower(CAST(svce AS TEXT)) LIKE '%account%' "
        "OR lower(CAST(svce AS TEXT)) LIKE '%user%' OR lower(CAST(svce AS TEXT)) LIKE '%token%' THEN 'login_related_name' "
        "ELSE 'unclassified' END" : @"'unclassified'";
    NSString *query = [NSString stringWithFormat:@"SELECT %@, COUNT(*) FROM %@ WHERE agrp = ? GROUP BY 1", category, table];
    sqlite3_stmt *statement = NULL;
    int status = sqlite3_prepare_v2(database, query.UTF8String, -1, &statement, NULL);
    if (status != SQLITE_OK) {
        if (statement) sqlite3_finalize(statement);
        return @{@"table": table, @"status": @(status), @"state": @"schema_or_access_unavailable"};
    }
    sqlite3_bind_text(statement, 1, TargetGroup.UTF8String, -1, SQLITE_TRANSIENT);
    NSMutableArray *counts = [NSMutableArray new];
    while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
        const unsigned char *categoryText = sqlite3_column_text(statement, 0);
        [counts addObject:@{@"category": categoryText ? @((const char *)categoryText) : @"unknown",
                            @"count": @(sqlite3_column_int64(statement, 1))}];
    }
    sqlite3_finalize(statement);
    return @{@"table": table, @"status": @(status), @"counts": counts,
             @"state": status == SQLITE_DONE ? @"metadata_counts_only" : @"query_failed"};
}

static NSDictionary *ServiceStorage(sqlite3 *database)
{
    sqlite3_stmt *statement = NULL;
    int status = sqlite3_prepare_v2(database,
        "SELECT typeof(svce), COUNT(*), MIN(length(svce)), MAX(length(svce)) FROM genp WHERE agrp = ? GROUP BY typeof(svce)",
        -1, &statement, NULL);
    if (status != SQLITE_OK) {
        if (statement) sqlite3_finalize(statement);
        return @{@"status": @(status)};
    }
    sqlite3_bind_text(statement, 1, TargetGroup.UTF8String, -1, SQLITE_TRANSIENT);
    NSMutableArray *storage = [NSMutableArray new];
    while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
        const unsigned char *type = sqlite3_column_text(statement, 0);
        [storage addObject:@{@"type": type ? @((const char *)type) : @"unknown",
                             @"count": @(sqlite3_column_int64(statement, 1)),
                             @"minimum_length": @(sqlite3_column_int64(statement, 2)),
                             @"maximum_length": @(sqlite3_column_int64(statement, 3))}];
    }
    sqlite3_finalize(statement);
    return @{@"status": @(status), @"service_column_structure_only": storage};
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (argc != 1) return 2;
        sqlite3 *database = NULL;
        const char *databasePath = "/rootfs/private/var/Keychains/keychain-2.db";
        int status = sqlite3_open_v2(databasePath, &database,
                                     SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL);
        if (status != SQLITE_OK) {
            if (database) sqlite3_close(database);
            database = NULL;
            databasePath = "/private/var/Keychains/keychain-2.db";
            status = sqlite3_open_v2(databasePath, &database,
                                     SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL);
        }
        NSMutableDictionary *report = [@{@"mode": @"read_only_keychain_metadata",
            @"access_group": TargetGroup, @"open_status": @(status), @"database_path": @(databasePath),
            @"limitations": @[@"name_categories_are_not_proof_of_record_purpose",
                                @"no_account_label_password_token_or_encrypted_data_selected",
                                @"no_update_delete_identifier_generation_or_app_injection"]} mutableCopy];
        if (status == SQLITE_OK) {
            sqlite3_busy_timeout(database, 1500);
            BOOL queryOnly = sqlite3_exec(database, "PRAGMA query_only=ON", NULL, NULL, NULL) == SQLITE_OK;
            BOOL transaction = queryOnly && sqlite3_exec(database, "BEGIN", NULL, NULL, NULL) == SQLITE_OK;
            report[@"database_readonly"] = @(sqlite3_db_readonly(database, "main") == 1);
            report[@"transaction_opened"] = @(transaction);
            if (transaction) {
                report[@"tables"] = @[
                    CountTable(database, @"genp", YES), CountTable(database, @"inet", NO)
                ];
                report[@"service_storage"] = ServiceStorage(database);
                sqlite3_exec(database, "ROLLBACK", NULL, NULL, NULL);
            }
        }
        if (database) sqlite3_close(database);
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
        if (!data) return 1;
        fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
        return status == SQLITE_OK ? 0 : 1;
    }
}
