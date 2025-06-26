/**
 * @description       : This is a Queueable class to retry the Uptiq AI Callout.
 * @author            : Supriyo Seni
 * @group             : Queueable
 * @last modified on  : 06-19-2025
 * @last modified by  : Supriyo Seni
**/
// Queueable class for asynchronous retry of AI agent callouts
// Implements Database.AllowsCallouts to enable HTTP requests in async context
public class UptiqAICalloutRetryQueueable implements Queueable, Database.AllowsCallouts {
    // Transaction ID from the original AI request that needs to be retried
    private String transactionId;
    // Loan Condition record ID that this retry is associated with
    private String loanConditionId;

    /**
    * @description | Constructor
    * @author Supriyo Seni | 06-18-2025 
    * @param transactionId 
    * @param loanConditionId 
    **/
    public UptiqAICalloutRetryQueueable(String transactionId,String loanConditionId) {
        // Initialize the queueable with the transaction and loan condition identifiers
        this.transactionId = transactionId;
        this.loanConditionId = loanConditionId;
    }

    /**
    * @description | This method is called for each batch of records to process them.
    * @author Supriyo Seni | 06-13-2025 
    * @param context 
    **/
    public void execute(QueueableContext context) {
        // Create HTTP instance for making the retry callout
        Http httpInst = new Http();
        try {
            // Generate a new execution ID for this retry attempt
            String executionId = UUID.randomUUID().toString();
            // Prepare the request payload specifically for fetching results from a previous transaction
            String requestPayload = prepareRequestPayload(transactionId, executionId);

            // Set up the HTTP request for the AI agent retry callout
            HttpRequest requestObj = new HttpRequest();
            requestObj.setEndpoint(UptiqAIConstants.UPTIQ_AI_AGENT_CALLOUT_CREDENTIAL);
            requestObj.setMethod(UptiqAIConstants.POST);
            requestObj.setHeader(UptiqAIConstants.CONTENT_TYPE, UptiqAIConstants.APPLICATION_JSON);
            requestObj.setTimeout(UptiqAIConstants.MAX_TIME_OUT_LIMIT);
            requestObj.setBody(requestPayload);

            // Execute the HTTP callout to retry the AI request
            HttpResponse responseObj = httpInst.send(requestObj);
            String responseBody = responseObj.getBody();
            
            // Create an instance of the main callout class to reuse its methods
            UptiqAIAgentCallout  uptiqAIAgentCalloutInst = new UptiqAIAgentCallout();
            // Insert a new AI response record to track this retry attempt
            Id aiResponseId = uptiqAIAgentCalloutInst.insertAIResponseRecord(loanConditionId);
            
            // Store request and response as files if the feature is enabled in settings
            if(Uptiq_AI_Rule_Engine__c.getInstance().Store_Uptiq_Request_and_Response__c){
                uptiqAIAgentCalloutInst.storeAsFiles(requestPayload,responseBody,aiResponseId);
            }
            
            // Process the response if the callout was successful (HTTP 200)
            if (responseObj.getStatusCode() == 200) {
                // Update the loan condition rules with the AI response data
                uptiqAIAgentCalloutInst.updateRulesWithAIResponse(responseBody,aiResponseId,loanConditionId);
            }else{
                // Throw exception if the retry callout failed
                throw new CustomException('Failed to retry callout for loan condition' + loanConditionId + ': ' + responseObj.getStatus() + ' - ' + responseBody);
            }
        } catch (Exception excepInst) {
            // Log any errors that occur during the retry process
            Database.insert(UptiqAIUtil.createUptiqAIErrorLog(excepInst, UptiqAICalloutRetryQueueable.class.getName(), new List<String>{'Uptiq Transaction Id : ' + transactionId}));
            // Send failure notification email to administrators
            UptiqAIUtil.sendFailureEmail(excepInst.getMessage());
        }
    }

    /**
     * @description | This method prepares the request payload for the Uptiq AI callout.
     * @param transactionId 
     * @param executionId 
     * @return String 
     **/
    private String prepareRequestPayload(String transactionId, String executionId) {
        // Create request parser instance for retry-specific payload structure
        UptiqAIRetryRequestParser requestBodyInst = new UptiqAIRetryRequestParser();
        
        // Set up the basic request structure for fetching previous results
        requestBodyInst.executionId = executionId;
        requestBodyInst.integrationId = UptiqAIConstants.UPTIQ_AGENT_ID_MERGE_FIELD;
        requestBodyInst.disableNLP = true; // Disable natural language processing for result fetch
        requestBodyInst.miniAgentIntegrationId = UptiqAIConstants.UPTIQ_SUBAGENT_ID_MERGE_FIELD;
        // Use fetch result intent instead of validate rule intent for retry operations
        requestBodyInst.intent = UptiqAIConstants.UPTIQ_FETCH_RESULT_INTENT_MERGE_FIELD;
        
        // Set user input to contain only the original transaction ID for result retrieval
        requestBodyInst.userInput = new Map<String, String>{
            'transactionId' => transactionId
        };
        
        // Serialize the request object to JSON format
        return JSON.serialize(requestBodyInst);
    }

    /**
     * @description | Inner class to hold request body structure for Uptiq AI
     * This class defines the structure for retry requests which is simpler than initial requests
     * since we're only fetching results from an existing transaction
     */
    private class UptiqAIRetryRequestParser {
        public String executionId;              // New execution ID for this retry attempt
        public String integrationId;            // AI agent integration identifier
        public Boolean disableNLP;              // Flag to disable natural language processing
        public String miniAgentIntegrationId;   // Sub-agent identifier
        public String intent;                   // Intent for this request (fetch results)
        public Map<String, String> userInput;   // Simple key-value input containing transaction ID
    }
}