/**
 * @description       : This Job is used to Validate the Uptiq AI Rule.
 * @author            : Supriyo Seni
 * @group             : Batch Job
 * @last modified on  : 06-26-2025
 * @last modified by  : Supriyo Seni
**/
// Global batch class for processing documents and validating AI rules
// Implements Database.Batchable to process records in chunks
// Implements Database.AllowsCallouts to enable HTTP requests to AI agent
// Implements Database.Stateful to maintain state across batch executions
global class UptiqAIRuleValidationBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {

    // List of contentVersion Ids that need to be processed by the AI agent
    private List<Id> documentIdList;

    // The loan condition record that contains the rules to be validated against the documents
    private FullSkope__Loan_Condition__c loanConditionObj;

    // List of parsed signed URL responses that contain upload information for each document
    // These responses are used to map documents to their storage locations in the AI system
    private List<UptiqAISignedURLController.UptiqAISignedURLResponseParser> signedUrlParserList;

    // Counter to track the current document being processed (used to match with signedUrlParserList)
    private Integer docCountMatchIndex = 0;

    // List to accumulate all successfully generated storage IDs from processed documents
    // This list is maintained across batch executions due to Database.Stateful
    List<String> storageIdList = new List<String>();

    /**
    * @description | Constructor to initialize the batch class with required inputs
    * @author Supriyo Seni | 06-13-2025 
    * @param loanConditionObj - Loan condition record
    * @param documentIdList - List of documents to validate
    * @param signedUrlParserList - Corresponding signed URL parser responses
    **/
    public UptiqAIRuleValidationBatch(FullSkope__Loan_Condition__c loanConditionObj, List<Id> documentIdList, List<UptiqAISignedURLController.UptiqAISignedURLResponseParser> signedUrlParserList) {
        // Initialize the batch with the loan condition that contains rules to validate
        this.loanConditionObj = loanConditionObj;
        // Initialize with the list of document Ids that need to be processed
        this.documentIdList = documentIdList;
        // Initialize with the corresponding signed URL responses for document uploads
        this.signedUrlParserList = signedUrlParserList;
    }

    // Start method defines what records to process - returns the list of documents
    public Database.querylocator start(Database.BatchableContext bc){

        return Database.getQueryLocator([SELECT Id, 
                                                Title, 
                                                VersionData,
                                                ContentDocumentId,
                                                FileType,
                                                PathOnClient
                                        FROM ContentVersion
                                        WHERE Id IN : documentIdList
                                        AND IsLatest = true 
                                        ORDER BY ContentSize DESC]);
    }    

    /**
    * @description | This method is called for each batch of records to process them.
    * @author Supriyo Seni | 06-13-2025 
    * @param bc - Batch context
    * @param scope - Current batch of blob records
    **/
    public void execute(Database.BatchableContext bc, List<ContentVersion> scope) {
        // Process one document at a time (scope contains one blob record)
        ContentVersion contentVersionObj = scope[0];
        try { 
            // Generate storage ID for the current document by uploading it to the AI system
            // Uses the corresponding signed URL response from the list based on docCountMatchIndex
            String storageId = UptiqAISignedURLController.getUptiqStorageId(loanConditionObj.Id, contentVersionObj, signedUrlParserList[docCountMatchIndex]);
            
            // Add the storage ID to the list if it was successfully generated
            // This storage ID will be used to reference the document in AI agent requests
            if (String.isNotBlank(storageId)) {
                storageIdList.add(storageId);
            }

            // Increment counter to process the next document and its corresponding signed URL response
            docCountMatchIndex++;    
        } catch (Exception excepInst) {
            // Log any errors that occur during document processing
            Database.insert(UptiqAIUtil.createUptiqAIErrorLog(excepInst, UptiqAIRuleValidationBatch.class.getName(), new List<String>{loanConditionObj.Id}));
            // Send failure notification email to administrators
            UptiqAIUtil.sendFailureEmail(excepInst.getMessage());
        }
    }

    /**
    * @description | This method is called at the end of the batch job to handle any post-processing operations.
    * @author Supriyo Seni | 06-13-2025 
    * @param bc - Batch context
    **/
    public void finish(Database.BatchableContext bc) {
        // Storage ID validation check
        if(storageIdList.size() != documentIdList.size()){
            return;
        }
        // Create instance of the AI agent callout class to initiate rule validation
        UptiqAIAgentCallout uptiqAIAgentCalloutInst = new UptiqAIAgentCallout();
        try {
            // Initiate the AI agent callout with the loan condition and all collected storage IDs
            // This will send the documents and rules to the AI agent for validation
            uptiqAIAgentCalloutInst.initiateCallout(loanConditionObj, storageIdList);
        } catch (Exception excepInst) {
            // Handle specific timeout scenarios with retry logic
            if (excepInst.getMessage().contains(UptiqAIConstants.READ_TIME_OUT) && uptiqAIAgentCalloutInst.transactionId != null) {
                // Get retry delay configuration from custom settings (default to 5 minutes if not set)
                Integer delayInMins = Integer.valueOf(Uptiq_AI_Rule_Engine__c.getInstance().Uptiq_Retry_Delay_In_Minutes__c ?? 5);
                
                // Enqueue a retry job with the specified delay using the transaction ID from the failed request
                // This allows the system to attempt to retrieve results from the AI agent later
                System.enqueueJob(new UptiqAICalloutRetryQueueable(uptiqAIAgentCalloutInst.transactionId, loanConditionObj.Id), delayInMins);         
            } else {
                // For non-timeout errors, log the error and send notification
                Database.insert(UptiqAIUtil.createUptiqAIErrorLog(excepInst, UptiqAIRuleValidationBatch.class.getName(), new List<String>{loanConditionObj.Id}));
                UptiqAIUtil.sendFailureEmail(excepInst.getMessage());
            }
        }
    }
}