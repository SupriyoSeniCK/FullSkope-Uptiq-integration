/**
 * @description       : This class is used to handle the Uptiq AI callout for processing loan conditions. 
 *                      It orchestrates the entire workflow from retrieving loan documents to initiating AI processing.
 *                      Main workflow: Fetch loan conditions → Get linked documents → Generate signed URLs → Upload documents → Execute AI validation
 * @author            : Supriyo Seni
 * @group             : API
 * @last modified on  : 06-24-2025
 * @last modified by  : Supriyo Seni
**/
public with sharing class UptiqAIController {

    /**
    * @description | MAIN ENTRY POINT: This method is the entry point for the Uptiq AI callout. 
    *              | WORKFLOW: It processes a list of Loan Condition Ids, retrieves associated documents, and initiates the AI processing.
    *              | STEPS: 1) Validate input → 2) Fetch loan conditions & documents → 3) Filter valid files → 4) Generate signed URLs → 5) Initiate AI processing
    * @author Supriyo Seni | 06-13-2025 
    * @param loanConditionIdList - List of Loan Condition record IDs to process
    **/
    @InvocableMethod(label='Loan Condition: Run UPTIQ AI Rule Engine' description='Processes loan conditions by retrieving associated documents and calling Uptiq AI Agent')    
    public static void uptiqCalloutInvocable(List<String> loanConditionIdList){
        // Variables to store document processing data
        Set<Id> contentDocIdSet = new Set<Id>();                                    // Set of all content document IDs
        Map<Id, Id> docIdVsLoanConditionIdMap = new Map<Id, Id>();                 // Maps document ID to loan condition ID
        Integer validDocumentCount = 0;                                             // Counter for valid documents (supported file types)
        Map<FullSkope__Loan_Condition__c, List<Id>> loanConditionVsDocsIdMap = new Map<FullSkope__Loan_Condition__c, List<Id>>(); // Maps each loan condition to its documents
        
        try{
            // VALIDATION: Early return if no loan conditions provided
            if(loanConditionIdList.isEmpty()) {
                return;
            }

            // STEP 1: Fetch loan conditions with their associated data
            // Query fetches: loan condition details + related rules (for UPTIQ AI agent) + linked documents
            Map<Id, FullSkope__Loan_Condition__c> idVsLoanConditionMap = new Map<Id, FullSkope__Loan_Condition__c>([SELECT Id,
                                                                                                                            Name,
                                                                                                                            FullSkope__Loan_Applicant__c,
                                                                                                                            FullSkope__Condition_Name__c,
                                                                                                                            // Subquery: Get rules assigned to UPTIQ AI agent
                                                                                                                            (SELECT id,Name,
                                                                                                                                    FullSkope__Inquiry__c,
                                                                                                                                    FullSkope__Reviewing_Party__c 
                                                                                                                            FROM FullSkope__Rules__r
                                                                                                                            WHERE FullSkope__Reviewing_Party__c =: UptiqAIConstants.UPTIQ_AI_AGENT), 
                                                                                                                            // Subquery: Get all linked documents
                                                                                                                            (SELECT Id, 
                                                                                                                                    ContentDocumentId,
                                                                                                                                    LinkedEntityId 
                                                                                                                            FROM ContentDocumentLinks)
                                                                                                                    FROM FullSkope__Loan_Condition__c
                                                                                                                    WHERE Id IN : loanConditionIdList
                                                                                                                    WITH SYSTEM_MODE]);

            // STEP 2: Extract all ContentDocumentLinks from the loan conditions
            List<ContentDocumentLink> contentDocLinkList = getContentDocumentList(idVsLoanConditionMap.values());

            // STEP 3: Build collections for document processing
            // Loop through each document link to create mapping structures
            for(ContentDocumentLink eachDocLink : contentDocLinkList){
                contentDocIdSet.add(eachDocLink.ContentDocumentId);                     // Collect all unique document IDs
                docIdVsLoanConditionIdMap.put(eachDocLink.ContentDocumentId, eachDocLink.LinkedEntityId); // Map each document to its loan condition
            }

            // STEP 4: Fetch the latest version of each document
            // Query gets: document metadata + binary data (VersionData) for AI processing
            List<ContentVersion> contentVersionList = [SELECT Id, 
                                                                Title, 
                                                                ContentDocumentId,
                                                                FileType
                                                        FROM ContentVersion
                                                        WHERE ContentDocumentId IN :contentDocIdSet
                                                        AND IsLatest = true 
                                                        WITH SYSTEM_MODE];  

            // ERROR HANDLING: Throw error if no documents are found for processing
            UptiqAIUtil.throwErrorOnCondition(contentVersionList.isEmpty(), 'No documents found in Loan Conditions : ' +  loanConditionIdList);

            // STEP 5: Filter documents by supported file types and organize by loan condition
            // Only documents with valid file types (PDF, JPEG, JPG, PNG) are processed
            for (ContentVersion eachContentVersion : contentVersionList) {
                // Skip unsupported file types
                if(!(UptiqAIConstants.VALID_FILE_TYPE_LIST).contains(eachContentVersion.FileType)){
                    continue;
                }
                validDocumentCount++; // Increment counter for valid documents
                
                // Find which loan condition this document belongs to
                Id loanConditionId = docIdVsLoanConditionIdMap.get(eachContentVersion.ContentDocumentId);
                FullSkope__Loan_Condition__c loanConditionObj = idVsLoanConditionMap.get(loanConditionId);
                
                // Group documents by loan condition (initialize list if not exists)
                if (!loanConditionVsDocsIdMap.containsKey(loanConditionObj)) {
                    loanConditionVsDocsIdMap.put(loanConditionObj, new List<Id>());
                }
                loanConditionVsDocsIdMap.get(loanConditionObj).add(eachContentVersion.Id);
            }

            // STEP 6: Generate signed URLs for secure document access
            // These URLs allow the AI service to securely access documents for processing
            List<UptiqAISignedURLController.UptiqAISignedURLResponseParser> signedUrlParserList = UptiqAISignedURLController.getUptiqSignedUrls(validDocumentCount);

            // STEP 7: Initiate the AI processing workflow
            // Upload documents using signed URLs and trigger rule validation
            initiateDocumentUploadCallout(idVsLoanConditionMap.values(),loanConditionVsDocsIdMap, signedUrlParserList);
            
        }catch(Exception excepInst){
            // ERROR HANDLING: Log the error and send notification email
            Database.insert(UptiqAIUtil.createUptiqAIErrorLog(excepInst, UptiqAIController.class.getName(),loanConditionIdList));
            UptiqAIUtil.sendFailureEmail(excepInst.getMessage());
        }
    }

    /**
    * @description | HELPER METHOD: Extracts ContentDocumentLink records from loan conditions
    *              | PURPOSE: Converts the nested ContentDocumentLinks relationship into a flat list for easier processing
    * @author Supriyo Seni | 06-18-2025 
    * @param loanConditionList - List of Loan Condition records (with ContentDocumentLinks populated)
    * @return List<ContentDocumentLink> - Flattened list of all document links
    **/
    public static List<ContentDocumentLink>  getContentDocumentList(List<FullSkope__Loan_Condition__c> loanConditionList){
        List<ContentDocumentLink> contentDocLinkList = new List<ContentDocumentLink>();
        
        // Loop through each loan condition and extract its document links
        for (FullSkope__Loan_Condition__c eachLoanCondition : loanConditionList) {
            // Check if loan condition has any linked documents
            if(eachLoanCondition.ContentDocumentLinks != null && !eachLoanCondition.ContentDocumentLinks.isEmpty()) {
                contentDocLinkList.addAll(eachLoanCondition.ContentDocumentLinks); // Add all document links to the flat list
            }
        }
        return contentDocLinkList;
    }

    /**
    * @description | ORCHESTRATION METHOD: Manages the document upload process and batch execution
    *              | PURPOSE: Maps loan conditions to documents and signed URLs, then prepares for batch processing
    *              | WORKFLOW: 1) Group signed URLs by loan condition → 2) Handle conditions with no valid documents → 3) Execute batch processing
    * @author Supriyo Seni | 06-18-2025 
    * @param loanConditionList - List of loan Condition Records
    * @param loanConditionVsDocsIdMap - Mapping of loan conditions to their associated documents
    * @param responseParserList - List of signed URL response objects (one for each valid document)
    **/
    public static void initiateDocumentUploadCallout(List<FullSkope__Loan_Condition__c> loanConditionList,
            Map<FullSkope__Loan_Condition__c, List<Id>> loanConditionVsDocsIdMap, 
            List<UptiqAISignedURLController.UptiqAISignedURLResponseParser> responseParserList){
        // Collections for organizing signed URLs by loan condition
        // List of lists - each inner list contains URLs for one loan condition
        List<List<UptiqAISignedURLController.UptiqAISignedURLResponseParser>> signedUrlGroupList = new List<List<UptiqAISignedURLController.UptiqAISignedURLResponseParser>>(); 
        // Temporary list for building each loan condition's URL group
        List<UptiqAISignedURLController.UptiqAISignedURLResponseParser> signedUrlParserList = new List<UptiqAISignedURLController.UptiqAISignedURLResponseParser>(); 
        List<FullSkope_Log__c> uptiqAILogList = new List<FullSkope_Log__c>(); // Error logs for conditions with no valid documents
        
        // STEP 1: Calculate document count per loan condition
        // This helps us know how many signed URLs belong to each loan condition
        List<Integer> eachConditionDocCountList = new List<Integer>();
        for(FullSkope__Loan_Condition__c loanConditionObj : loanConditionList){
            List<Id> documentIdList = loanConditionVsDocsIdMap?.get(loanConditionObj);
            if(documentIdList != null && documentIdList.size() > 0){
                eachConditionDocCountList.add(documentIdList.size()); // Add document count for this condition
            }else{
                // ERROR CASE: Log error for loan conditions with no valid documents
                FullSkope_Log__c  aiAgentLogObj = new FullSkope_Log__c();
                aiAgentLogObj.Name = UptiqAIController.class.getName();
                aiAgentLogObj.Message__c = 'No valid file found in Loan Condition: ' + loanConditionObj.Id + '. Please note only PDF, JPEG, JPG, PNG files are allowed.';
                aiAgentLogObj.Time__c = System.now();
                uptiqAILogList.add(aiAgentLogObj);
            }
        }

        // STEP 2: Split signed URLs into groups - each group corresponds to one loan condition
        // Algorithm: Use document counts to divide the flat signed URL list into sublists
        Integer singedUrlListCount = 0;        // Index tracking which loan condition we're processing
        Integer currentIndex = 0;              // Counter for current loan condition's URLs
        for(UptiqAISignedURLController.UptiqAISignedURLResponseParser eachResponseParser : responseParserList){
            currentIndex++;
            signedUrlParserList.add(eachResponseParser); // Add URL to current loan condition's group
            
            // Check if we've collected all URLs for current loan condition
            if(currentIndex == eachConditionDocCountList[singedUrlListCount]){ 
                signedUrlGroupList.add(signedUrlParserList);                           // Save current group
                signedUrlParserList = new List<UptiqAISignedURLController.UptiqAISignedURLResponseParser>(); // Reset for next group
                singedUrlListCount++;                                                   // Move to next loan condition
                currentIndex = 0;                                                       // Reset counter
            }
            
            // Safety check: Stop if we've processed all loan conditions
            if(singedUrlListCount == eachConditionDocCountList.size()){
                break;
            }
        }
        
        // STEP 3: Execute batch processing for each loan condition
        intiateDocumentUploadInBatch(loanConditionVsDocsIdMap,signedUrlGroupList);
        
        // STEP 4: Insert error logs for conditions with no valid documents
        if(!uptiqAILogList.isEmpty()){
            Database.insert(uptiqAILogList,false,AccessLevel.SYSTEM_MODE);
        }
    }

    /**
    * @description | BATCH COORDINATION METHOD: Executes rule validation batch for each loan condition
    *              | PURPOSE: Iterates through loan conditions and triggers batch processing for each one with valid documents
    * @author Supriyo Seni | 06-18-2025 
    * @param loanConditionVsDocsIdMap - Loan Condition Vs Documents Map
    * @param signedUrlGroupList - List of signed URL lists (each inner list corresponds to one loan condition)
    **/
    public static void intiateDocumentUploadInBatch(Map<FullSkope__Loan_Condition__c, List<Id>> loanConditionVsDocsIdMap, List<List<UptiqAISignedURLController.UptiqAISignedURLResponseParser>> signedUrlGroupList){
        // Execute validation batch for each condition with corresponding documents and signed URLs
        Integer docCountMatchIndex = 0; // Index to match loan conditions with their signed URL groups
        // Check if the number of batch jobs to be processed exceeds the limit of 5 per transaction
        if (loanConditionVsDocsIdMap.keySet().size() > 5) {
            throw new CustomException('A maximum of 5 loan conditions can be processed in a single transaction. Currently attempting to process ' + loanConditionVsDocsIdMap.keySet().size() + 
                    '. Please contact your system administrator for further assistance.');
        }
        
        for(FullSkope__Loan_Condition__c loanConditionObj : loanConditionVsDocsIdMap.keyset()){
            List<Id> documentIdList = loanConditionVsDocsIdMap.get(loanConditionObj);
            
            // Only process loan conditions that have valid documents
            if(documentIdList != null && documentIdList.size() > 0){
                // Execute batch with: loan condition + its documents + corresponding signed URLs
                executeRuleValidationBatch(loanConditionObj, documentIdList, signedUrlGroupList[docCountMatchIndex]);
                docCountMatchIndex++; // Move to next signed URL group
            }
        }
    }

    /**
    * @description | BATCH EXECUTION METHOD: Triggers the actual batch job for AI processing
    *              | PURPOSE: Validates that signed URLs match document count, then executes the document upload batch
    *              | BATCH SIZE: Uses batch size of 1 to ensure proper processing per loan condition
    * @author Supriyo Seni | 06-18-2025 
    * @param loanConditionObj - Loan Condition record to process
    * @param documentIdList - Associated Docs for this loan condition
    * @param signedUrlParserList - Signed URLs corresponding to the documents (must match document count)
    **/
    public static void executeRuleValidationBatch(FullSkope__Loan_Condition__c loanConditionObj, List<Id> documentIdList, List<UptiqAISignedURLController.UptiqAISignedURLResponseParser> signedUrlParserList){
        // VALIDATION: Ensure we have enough signed URLs for all documents
        if(signedUrlParserList != null && signedUrlParserList.size() >= documentIdList.size()){
            // Execute the document upload and Agent callout batch with size 1
            // Batch will handle: document upload to AI service + rule validation execution
            Database.executeBatch(new UptiqAIRuleValidationBatch(loanConditionObj, documentIdList, signedUrlParserList), 1);
        }
    }
}