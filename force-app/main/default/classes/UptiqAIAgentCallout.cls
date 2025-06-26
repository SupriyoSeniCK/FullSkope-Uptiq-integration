/**
 * @description       : This class contains the callout methods for Uptiq AI Agent
 * @author            : Supriyo Seni
 * @group             : API
 * @last modified on  : 06-25-2025
 * @last modified by  : Supriyo Seni
**/
public with sharing class UptiqAIAgentCallout {

    // Transaction ID to track the current AI agent request
    public String transactionId;

    /**
    * @description | Method to initiate the callout to Uptiq AI Agent
    * @author Supriyo Seni | 06-13-2025 
    * @param loanConditionObj 
    * @param storageIdList 
    **/
    public void initiateCallout(FullSkope__Loan_Condition__c loanConditionObj, List<String> storageIdList) {
        // Extract rules from the loan condition object
        List<FullSkope__Rule__c> rulesList = loanConditionObj.FullSkope__Rules__r;
        
        // Validate that rules exist for the loan condition
        if (rulesList == null || rulesList.isEmpty()) {
            throw new CustomException('Rules are missing for Loan Condition: ' + loanConditionObj.Id);
        }
        
        // Validate that storage IDs are provided (for document references)
        if (storageIdList == null || storageIdList.isEmpty()) {
            throw new CustomException('Storage IDs are missing for Loan Condition: ' + loanConditionObj.Id);
        }
        
        // Build the JSON payload for the AI agent request
        String requestPayload = getPayload(loanConditionObj, rulesList, storageIdList);
        
        // Set up HTTP request to call the AI agent
        Http httpInst = new Http();
        HttpRequest requestInst = new HttpRequest();
        requestInst.setEndpoint(UptiqAIConstants.UPTIQ_AI_AGENT_CALLOUT_CREDENTIAL);
        requestInst.setMethod(UptiqAIConstants.POST);
        requestInst.setBody(requestPayload);
        requestInst.setHeader(UptiqAIConstants.CONTENT_TYPE, UptiqAIConstants.APPLICATION_JSON);
        requestInst.setTimeout(UptiqAIUtil.getUptiqTimeoutLimit());
        
        // Execute the HTTP callout
        HttpResponse responseInst = httpInst.send(requestInst);
        String responseBody = responseInst.getBody();
        
        // Create a record to track this AI response
        Id aiResponseId = insertAIResponseRecord(loanConditionObj.Id);
        
        // Store request and response as files if the setting is enabled
        if(Uptiq_AI_Rule_Engine__c.getInstance().Store_Uptiq_Request_and_Response__c){
            storeAsFiles(requestPayload,responseBody,aiResponseId);
        }
        
        // Check if the HTTP request was successful (status code 200)
        UptiqAIUtil.throwErrorOnCondition(responseInst.getStatusCode() != 200, 'Error in callout. Status code: ' 
                + responseInst.getStatusCode() + UptiqAIConstants.BLANK_SPACE + responseInst.getStatus() 
                + UptiqAIConstants.BLANK_SPACE + responseInst.getBody());
        
        // Process the AI response and update the related rules
        updateRulesWithAIResponse(responseInst.getBody(),aiResponseId, loanConditionObj.Id);
    }

    /**
    * @description | This method inserts the AI Response record
    * @author Supriyo Seni | 06-16-2025 
    * @param loanId 
    * @return Id 
    **/
    public Id insertAIResponseRecord(Id loanId){
        // Create a new AI response record to track this request
        FullSkope__Open_AI_Response__c  aiResponseObj = new FullSkope__Open_AI_Response__c();
        aiResponseObj.FullSkope__Loan_Condition__c = loanId;
        aiResponseObj.FullSkope__Request_Type__c = UptiqAIConstants.OCR_REQUEST_TYPE;
        
        // Insert the record with system mode to bypass sharing rules
        Database.insert(aiResponseObj, true, AccessLevel.SYSTEM_MODE);
        return aiResponseObj.id;
    }

    /**
    * @description | This method updates the rules with the AI Response
    * @author Supriyo Seni | 06-16-2025 
    * @param responseJson 
    * @param aiResponseId 
    * @param loanConditionId 
    **/
    public void updateRulesWithAIResponse(String responseJson,Id aiResponseId,Id loanConditionId){
        // Initialize variables for parsing the AI response
        UptiqAIAgentResponseParser.ParsedResultWrapper parseResponseInst = new UptiqAIAgentResponseParser.ParsedResultWrapper ();
        List<String> ruleIdList = new List<String>();
        Map<String,UptiqAIAgentResponseParser.RuleEvaluationWrapper> ruleNameVsInstMap = new Map<String,UptiqAIAgentResponseParser.RuleEvaluationWrapper>();
        
        // Parse the JSON response from the AI agent
        parseResponseInst = UptiqAIAgentResponseParser.parseRules(responseJson);
        
        // Check if parsing was successful, throw error if not
        UptiqAIUtil.throwErrorOnCondition(parseResponseInst.executionStatus == UptiqAIConstants.FAILURE, 'Errors in Uptiq AI Agent Response: ' + parseResponseInst.errorMessage);
        
        // Extract rule evaluations from the parsed response
        if (parseResponseInst.executionStatus == UptiqAIConstants.SUCCESS && parseResponseInst.ruleEvaluations != null) {
            for (UptiqAIAgentResponseParser.RuleEvaluationWrapper ruleParserInst : parseResponseInst.ruleEvaluations) {
                if (ruleParserInst.ruleId != null) {
                    ruleIdList.add(ruleParserInst.ruleId);
                    ruleNameVsInstMap.put(ruleParserInst.ruleId, ruleParserInst);
                }
            }
        }
        
        // Query existing rules to update with AI responses
        List<FullSkope__Rule__c> rulesToUpdateList = [SELECT Id, 
                                                                Name,
                                                                FullSkope__AI_Response__c,
                                                                FullSkope__Actual_Response__c, 
                                                                FullSkope__Review_Status__c,
                                                                FullSkope__Acceptable_Response__c,
                                                                FullSkope__Additional_Information__c
                                                        FROM FullSkope__Rule__c 
                                                        WHERE Name IN : ruleIdList
                                                        WITH SYSTEM_MODE];
        
        // Update each rule with the AI response data
        for(FullSkope__Rule__c ruleObj :  rulesToUpdateList){
            // Set AI response result
            ruleObj.FullSkope__AI_Response__c = ruleNameVsInstMap.get(ruleObj.Name)?.result;
            // Set AI reasoning/explanation
            ruleObj.FullSkope__Additional_Information__c = ruleNameVsInstMap.get(ruleObj.Name)?.reasoningAi;
            // Set actual response (same as AI response initially)
            ruleObj.FullSkope__Actual_Response__c = ruleNameVsInstMap.get(ruleObj.Name)?.result;
            // Determine if the rule passes, fails, or needs review
            ruleObj.FullSkope__Review_Status__c = determineReviewStatus(ruleObj.FullSkope__AI_Response__c,ruleObj.FullSkope__Acceptable_Response__c);
        }
        
        // Update the AI Response record with parsed data
        FullSkope__Open_AI_Response__c aiResponseObj = new FullSkope__Open_AI_Response__c(id = aiResponseId );
        aiResponseObj.FullSkope__Response_Message__c = JSON.serialize(parseResponseInst?.ruleEvaluations);
        aiResponseObj.FullSkope__Response_Code__c = 200;    
        aiResponseObj.FullSkope__Message_ID__c = parseResponseInst?.id;
        aiResponseObj.FullSkope__Run_ID__c = parseResponseInst?.id;
        aiResponseObj.FullSkope__Error_Message__c = parseResponseInst?.errorMessage;

        // Update the loan condition with execution details
        FullSkope__Loan_Condition__c loanConditionObj = new FullSkope__Loan_Condition__c(id = loanConditionId );
        loanConditionObj.FullSkope__Send_for_Review__c = false;
        loanConditionObj.FullSkope__Run_ID__c = parseResponseInst?.id;

        // Perform all database updates
        Database.update(rulesToUpdateList, true, AccessLevel.SYSTEM_MODE);
        Database.update(aiResponseObj, true, AccessLevel.SYSTEM_MODE);
        Database.update(loanConditionObj, true, AccessLevel.SYSTEM_MODE);
    }

    /**
    * @description | This method determines the review status of the rule
    * @author Supriyo Seni | 06-16-2025 
    * @param aiResponse 
    * @param acceptableResponse 
    * @return String 
    **/
    public static String determineReviewStatus(String aiResponse, String acceptableResponse) {
        // If AI response matches the acceptable response, rule passes
        if (aiResponse == acceptableResponse) {
            return UptiqAIConstants.PASS;
        } 
        // If AI response is not a clear YES/NO, mark as exception for manual review
        if (aiResponse != UptiqAIConstants.YES && aiResponse != UptiqAIConstants.NO) {
            return UptiqAIConstants.EXCEPTION_STRING;
        } 
        // If AI response doesn't match acceptable response, rule fails
        return UptiqAIConstants.FAIL;
    }

    /**
    * @description | This method stores the request and response payload as content files
    * @author Supriyo Seni | 06-16-2025 
    * @param requestPayload 
    * @param responsePayload 
    * @param aiResponseId 
    **/
    public void storeAsFiles(String requestPayload, String responsePayload, Id aiResponseId) {
        // Create a timestamp for unique file naming
        String timestamp = String.valueOf(System.now()).replace(UptiqAIConstants.BLANK_SPACE, UptiqAIConstants.UNDERSCORE)
                .replace(UptiqAIConstants.COLON, UptiqAIConstants.DASH);
        String dynamicFileName;
        List<ContentVersion> contentVersionList = new List<ContentVersion>();
        
        // Create content version for request payload if it exists
        if(String.isNotBlank(requestPayload)){
            ContentVersion requestContentontentObj = new ContentVersion();
            requestContentontentObj.ContentLocation = UptiqAIConstants.CONTENT_LOCATION;
            requestContentontentObj.VersionData = Blob.valueOf(requestPayload);
            // Generate dynamic filename with timestamp
            dynamicFileName = UptiqAIConstants.REQUEST_FILE_NAME + timestamp + UptiqAIConstants.DOT_TXT;
    
            requestContentontentObj.Title = dynamicFileName;
            requestContentontentObj.PathOnClient = dynamicFileName;
            contentVersionList.add(requestContentontentObj);
        }
        
        // Create content version for response payload if it exists
        if(String.isNotBlank(responsePayload)){
            ContentVersion responseContentontentObj = new ContentVersion();
            responseContentontentObj.ContentLocation = UptiqAIConstants.CONTENT_LOCATION;
            responseContentontentObj.VersionData = Blob.valueOf(responsePayload);
            // Generate dynamic filename with timestamp
            dynamicFileName = UptiqAIConstants.RESPONSE_FILE_NAME + timestamp + UptiqAIConstants.DOT_TXT;
    
            responseContentontentObj.Title = dynamicFileName;
            responseContentontentObj.PathOnClient = dynamicFileName;
            contentVersionList.add(responseContentontentObj);
        }

        // Insert the content versions
        Database.insert(contentVersionList, true, AccessLevel.SYSTEM_MODE);

        // Link the content documents to the AI response record
        List<ContentDocumentLink> contentDocList = new List<ContentDocumentLink>();
        for(ContentVersion eachContentVersion : [SELECT ContentDocumentId FROM ContentVersion WHERE Id =: contentVersionList WITH SYSTEM_MODE]) {
            ContentDocumentLink conDocLinkObj = new ContentDocumentLink();
            conDocLinkObj.LinkedEntityId = aiResponseId; // Link to AI response record
            conDocLinkObj.ContentDocumentId = eachContentVersion.ContentDocumentId;
            conDocLinkObj.Visibility = UptiqAIConstants.ALL_USERS;
            conDocLinkObj.shareType = UptiqAIConstants.SHARE_TYPE; 
            contentDocList.add(conDocLinkObj);
        }
        Database.insert(contentDocList, true, AccessLevel.SYSTEM_MODE);
    }

    /**
    * @description | This method is used to generate the payload for the AI Request
    * @author Supriyo Seni | 06-13-2025 
    * @param loanConditionObj 
    * @param rulesList 
    * @param storageIdList 
    * @return String 
    **/
    public String getPayload(FullSkope__Loan_Condition__c loanConditionObj, List<FullSkope__Rule__c> rulesList,List<String> storageIdList){
        // Create the main request wrapper
        UptiqAIRequestWrapper reqWrapperInst = new UptiqAIRequestWrapper();
        
        // Generate a unique execution ID for this request
        UUID randomUuid = UUID.randomUUID();
        transactionId = String.valueOf(randomUuid);
        reqWrapperInst.executionId = String.valueOf(randomUuid);
        reqWrapperInst.integrationId = UptiqAIConstants.UPTIQ_AGENT_ID_MERGE_FIELD;
        reqWrapperInst.disableNLP = true; // Disable natural language processing
        reqWrapperInst.miniAgentIntegrationId = UptiqAIConstants.UPTIQ_SUBAGENT_ID_MERGE_FIELD;
        reqWrapperInst.intent = UptiqAIConstants.UPTIQ_VALIDATE_RULE_INTENT_MERGE_FIELD;

        // Create the user input wrapper
        UptiqAIUserInputWrapper inputWrapperInst = new UptiqAIUserInputWrapper();
        inputWrapperInst.transactionId = reqWrapperInst.executionId;
        // Get reference data for the loan applicant
        inputWrapperInst.referenceData = getReferenceDate(loanConditionObj.FullSkope__Loan_Applicant__c);

        // Convert Salesforce rules to AI agent format
        inputWrapperInst.rules = new List<UptiqAIRuleWrapper>();
        for (FullSkope__Rule__c ruleObj : rulesList) {
            UptiqAIRuleWrapper aiRuleInst = new UptiqAIRuleWrapper();
            aiRuleInst.rule = ruleObj.FullSkope__Inquiry__c; // The rule question/inquiry
            aiRuleInst.ruleId = ruleObj.Name; // Unique identifier for the rule
            inputWrapperInst.rules.add(aiRuleInst);
        }

        // Convert document storage IDs to AI agent format
        inputWrapperInst.documents = new List<UptiqAIDocumentWrapper>();
        for (String storageId : storageIdList) {
            if(String.isBlank(storageId)){
                continue;
            }
            UptiqAIDocumentWrapper docWrapperInst = new UptiqAIDocumentWrapper();
            docWrapperInst.storageId = storageId; // Reference to stored document
            docWrapperInst.documentName = loanConditionObj.FullSkope__Condition_Name__c;
            inputWrapperInst.documents.add(docWrapperInst);
        }
        
        // Attach user input to main request
        reqWrapperInst.userInput = inputWrapperInst;
        
        // Serialize the entire request to JSON
        return JSON.serialize(reqWrapperInst);
    }

    /**
    * @description | This method is used to get the reference date for the loan condition
    * @author Supriyo Seni | 06-18-2025 
    * @param applicantId 
    * @return Map<String, Object> 
    **/
    public Map<String, Object> getReferenceDate(Id applicantId) {
        // Return null if no applicant ID provided
        if(applicantId == null){
            return null;
        }
        
        Map<String, Object> referenceDataMap = new Map<String, Object>();
        List<String> fieldNameList = new List<String>();
        
        // Get metadata configuration for JSON field mapping
        List<FullSkope__Dynamic_JSON_Settings__mdt> jsonMappingList = [SELECT MasterLabel,
                                                                                FullSkope__JSON_Label__c,
                                                                                FullSkope__Object_API_Name__c,
                                                                                FullSkope__Field_API_Name__c,
                                                                                FullSkope__Document_Type__c
                                                                        FROM FullSkope__Dynamic_JSON_Settings__mdt
                                                                        WITH SYSTEM_MODE];
        
        // Build list of fields to query based on metadata configuration
        for(FullSkope__Dynamic_JSON_Settings__mdt eachMapping : jsonMappingList) {
            if(eachMapping.FullSkope__Object_API_Name__c.equalsIgnoreCase(UptiqAIConstants.FULLSKOPE_LOAN_APPLICATION_API_NAME)) {
                fieldNameList.add(eachMapping.FullSkope__Field_API_Name__c);
            }
        }
        
        // Return null if no fields to query
        if(fieldNameList.isEmpty()){
            return null;
        }
        
        // Dynamic SOQL query to get applicant data
        List<FullSkope__Loan_Applicant__c> applicantList = Database.query('SELECT Id, ' + String.join(fieldNameList, ', ') 
                + ' FROM FullSkope__Loan_Applicant__c WHERE Id = \'' + String.escapeSingleQuotes(applicantId) + '\'');
        
        // Return null if applicant not found
        if(applicantList.isEmpty()) {
            return null;
        }
        
        // Map Salesforce field values to JSON labels for the AI agent
        for(FullSkope__Dynamic_JSON_Settings__mdt eachMapping : jsonMappingList) {
            if(eachMapping.FullSkope__Object_API_Name__c.equalsIgnoreCase(UptiqAIConstants.FULLSKOPE_LOAN_APPLICATION_API_NAME)) {
                String fieldValue = String.valueOf(applicantList[0].get(eachMapping.FullSkope__Field_API_Name__c));
                if(String.isNotBlank(fieldValue)){
                    referenceDataMap.put(eachMapping.FullSkope__JSON_Label__c,fieldValue);
                }
            }
        }
        return referenceDataMap;
    }

    /**
    * @description | This class is used to wrap the Uptiq AI Request
    * Main wrapper class for the entire AI agent request payload
    **/
    public class UptiqAIRequestWrapper {
        public String executionId;           // Unique ID for this execution
        public String integrationId;         // AI agent integration identifier
        public Boolean disableNLP;           // Flag to disable natural language processing
        public String miniAgentIntegrationId; // Sub-agent identifier
        public String intent;                // The intent/purpose of the request
        public UptiqAIUserInputWrapper userInput; // User input data
    }

    /**
    * @description | This class is used to wrap the Uptiq AI User Input
    * Contains the actual data to be processed by the AI agent
    **/
    public class UptiqAIUserInputWrapper {
        public String transactionId;                        // Transaction identifier
        public Map<String, Object> referenceData;          // Reference data from loan applicant
        public List<UptiqAIRuleWrapper> rules;             // List of rules to evaluate
        public List<UptiqAIDocumentWrapper> documents;     // List of documents to analyze
    }

    /**
    * @description | This class is used to wrap the Uptiq AI Rule
    * Represents a single rule/question to be evaluated by the AI
    **/
    public class UptiqAIRuleWrapper {
        public String rule;     // The rule text/question
        public String ruleId;   // Unique identifier for the rule
    }

    /**
    * @description | This class is used to wrap the Uptiq AI Document
    * Represents a document reference for the AI to analyze
    **/
    public class UptiqAIDocumentWrapper {
        public String storageId;     // Storage identifier for the document
        public String documentName;  // Name/title of the document
    }

}