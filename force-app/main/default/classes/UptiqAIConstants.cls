/**
 * @description       : This is a constant class for Uptiq AI Rule Engine Development.
 *                      Contains all static constants used across the Uptiq AI system to ensure
 *                      consistency, maintainability, and to avoid hardcoded values throughout the codebase.
 * @author            : Supriyo Seni
 * @group             : Constant class
 * @last modified on  : 06-26-2025
 * @last modified by  : Supriyo Seni
**/
public inherited sharing class UptiqAIConstants {

    // AI Agent Configuration - Constants for agent identification and credential management
    public static final String UPTIQ_AI_AGENT = 'Uptiq AI Agent';
    public static final String UPTIQ_AGENT_ID_MERGE_FIELD = '{!$Credential.UptiqAIRuleAgentExternalCredential.UptiqAgentId}';
    public static final String UPTIQ_SUBAGENT_ID_MERGE_FIELD = '{!$Credential.UptiqAIRuleAgentExternalCredential.UptiqSubagentId}';
    public static final String UPTIQ_FETCH_RESULT_INTENT_MERGE_FIELD = '{!$Credential.UptiqAIRuleAgentExternalCredential.UptiqGetResponseIntentName}';
    public static final String UPTIQ_VALIDATE_RULE_INTENT_MERGE_FIELD = '{!$Credential.UptiqAIRuleAgentExternalCredential.UptiqValidateRulesIntentName}';

    // File Processing - Constants for file operations and supported formats
    public static final String DOT_TXT = '.txt';
    public static final List<String> VALID_FILE_TYPE_LIST = new List<String>{'PDF', 'JPEG', 'JPG', 'PNG'};
    public static final String REQUEST_FILE_NAME = 'Uptiq_AI_Rule_Agent_Request_';
    public static final String RESPONSE_FILE_NAME = 'Uptiq_AI_Rule_Agent_Response_';
    public static final String OCR_REQUEST_TYPE = 'OCR';

    // Document Sharing - Constants for content sharing and access control
    public static final String ALL_USERS = 'AllUsers';
    public static final String SHARE_TYPE = 'V';
    public static final String CONTENT_LOCATION = 'S';

    // API Configuration - Constants for HTTP methods, headers, and endpoints
    public static final String POST = 'POST';
    public static final String PUT = 'PUT';
    public static final String CONTENT_TYPE = 'Content-Type';
    public static final String APPLICATION_JSON = 'application/json';
    public static final String APPLICATION_OCTET_STREAM = 'application/octet-stream';
    public static final String UPTIQ_SIGNED_URL_CALLOUT_CREDENTIAL = 'callout:UptiqGenerateSignedURLCredential';
    public static final String UPTIQ_AI_AGENT_CALLOUT_CREDENTIAL = 'callout:UptiqAIRuleAgentCredential';
    public static final Integer MAX_TIME_OUT_LIMIT = 120000;

    // Status and Response Values - Constants for operation results and validation outcomes
    public static final String SUCCESS = 'Success';
    public static final String FAILURE = 'Failure';
    public static final String PASS = 'Pass';
    public static final String FAIL = 'Fail';
    public static final String EXCEPTION_STRING = 'Exception';
    public static final String YES = 'Yes';
    public static final String NO = 'No';
    public static final String READ_TIME_OUT = 'Read timed out';

    // System Configuration - Constants for system-wide settings and object references
    public static final String FULLSKOPE_LOAN_APPLICATION_API_NAME = 'FullSkope__Loan_Applicant__c';
    public static final String ORG_WIDE_EMAIL_ADDRESS = 'case-support@fullskope.com';
    public static final String GENERIC_ERROR_MESSAGE = 'Something Went Wrong. Please contact your admin';
    public static final String FAILURE_NOTIFICATION_EMAIL_TEMPLATE = 'Uptiq_AI_Agent_Failure_Notification';
    public static final String ERROR_MESSAGE_MEREGE_FIELD = '{!errorMessage}';
    public static final String UNIQUE_STRING = '@#';

    // String Utilities - Common string literals and delimiters used throughout the system
    public static final String COMMA = ',';
    public static final String BLANK_SPACE = ' ';
    public static final String UNDERSCORE = '_';
    public static final String COLON = ':';
    public static final String DASH = '-';
    public static final String BLANK_STRING = '';
    public static final String UNDERSCORE_ID = '_id';
    public static final String ID_STRING = 'id';
}