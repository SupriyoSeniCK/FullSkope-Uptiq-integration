/**
 * @description       : This class contains utility methods for Uptiq AI
 * @author            : Supriyo Seni
 * @group             : Util Class
 * @last modified on  : 06-25-2025
 * @last modified by  : Supriyo Seni
**/
public inherited sharing class UptiqAIUtil {

    /**
    * @description | This method is used to check if the condition is true and throw a custom exception
    * @author Supriyo Seni | 06-13-2025 
    * @param condition - The condition to evaluate
    * @param errorMessage - The error message to throw if condition is true
    **/
    public static void throwErrorOnCondition(Boolean condition, String errorMessage) {
        if (String.isBlank(errorMessage)) {
            return; // Do nothing if the error message is blank
        }
        // Throw a custom exception if the condition is true
        if (condition) {
            throw new customException(errorMessage);
        }
    }

    /**
    * @description | This method is used to create a FullSkope_Log__c record for error logging
    * @author Supriyo Seni | 06-18-2025 
    * @param excepInst - The exception instance to log
    * @param className - The name of the class where the error occurred
    * @param paramsList - Optional related record Ids or parameters
    * @return FullSkope_Log__c - The populated log object
    **/
    public static FullSkope_Log__c createUptiqAIErrorLog(Exception excepInst, String className, List<String> paramsList) {
        FullSkope_Log__c aiAgentLogObj = new FullSkope_Log__c();
        aiAgentLogObj.Name = className;
        aiAgentLogObj.Message__c = excepInst.getMessage();
        aiAgentLogObj.Stack_Trace__c = excepInst.getStackTraceString();
        aiAgentLogObj.Time__c = System.now();
        aiAgentLogObj.Type__c = excepInst.getTypeName();
        aiAgentLogObj.Line_Number__c = String.valueOf(excepInst.getLineNumber());

        // Add additional information if paramsList is provided
        if (paramsList != null && !paramsList.isEmpty()) {
            aiAgentLogObj.Additional_Information__c = 'Related Record Ids : ' + String.join(paramsList, UptiqAIConstants.COMMA);
        }

        return aiAgentLogObj; // Return the populated log object
    }

    /**
    * @description | This method is used to send a failure notification email to configured recipients
    * @author Supriyo Seni | 06-17-2025 
    * @param errorMessage - The message to include in the email body
    **/
    public static void sendFailureEmail(String errorMessage) {
        try {
            // Retrieve configured email addresses from custom metadata
            String emails = Uptiq_AI_Rule_Engine__c.getInstance().Uptiq_Exception_Emails__c;
            List<String> emailList = String.isNotBlank(emails) ? emails.split(UptiqAIConstants.COMMA) 
                    : new List<String>{UserInfo.getUserEmail()}; // Fallback to current user email

            if (emailList.isEmpty() || String.isBlank(errorMessage)) {
                return; // Exit if there's no recipient or message
            }

            // Fetch the failure notification email template
            List<EmailTemplate> emailTemplateList = [SELECT Id, 
                                                            Name, 
                                                            HtmlValue, 
                                                            subject, 
                                                            DeveloperName
                                                        FROM EmailTemplate
                                                        WHERE DeveloperName =: UptiqAIConstants.FAILURE_NOTIFICATION_EMAIL_TEMPLATE
                                                        WITH SYSTEM_MODE
                                                        LIMIT 1];

            if (emailTemplateList.isEmpty()) {
                return; // Exit if template is not found
            }

            // Prepare the HTML email body by inserting the error message
            String htmlBody = emailTemplateList[0].HtmlValue;
            htmlBody = htmlBody.replace(UptiqAIConstants.ERROR_MESSAGE_MEREGE_FIELD, errorMessage);

            // Set up the email object
            Messaging.SingleEmailMessage mailObj = new Messaging.SingleEmailMessage();
            mailObj.setToAddresses(emailList);
            mailObj.setSubject(emailTemplateList[0].subject);
            mailObj.setHtmlBody(htmlBody);

            // Set org-wide email address if available
            List<OrgWideEmailAddress> orgEmailList = [SELECT Id 
                                                        FROM OrgWideEmailAddress
                                                        WHERE Address = :UptiqAIConstants.ORG_WIDE_EMAIL_ADDRESS
                                                        AND IsVerified = true
                                                        WITH SYSTEM_MODE
                                                        LIMIT 1];
            if (!orgEmailList.isEmpty()) {
                mailObj.setOrgWideEmailAddressId(orgEmailList[0].Id);
            }

            // Send the email
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mailObj });

        } catch (Exception e) {
            return; // Silently handle any exceptions during email sending
        }
    }

    /**
    * @description | This method returns the timeout limit configured for the UptiqAIJob
    * @author Supriyo Seni | 06-17-2025 
    * @return Integer - Timeout in milliseconds
    **/
    public static Integer getUptiqTimeoutLimit() {
        // Retrieve timeout value from custom metadata
        Decimal timeoutVal = Uptiq_AI_Rule_Engine__c.getInstance().Uptiq_Timeout_Limit_In_Miliseconds__c;

        if (timeoutVal != null && timeoutVal > 0 && timeoutVal <= UptiqAIConstants.MAX_TIME_OUT_LIMIT) {
            return timeoutVal.intValue(); // Return custom timeout value
        }

        // Return default value (120000 ms) if not configured or out of range
        return  UptiqAIConstants.MAX_TIME_OUT_LIMIT;
    }
}