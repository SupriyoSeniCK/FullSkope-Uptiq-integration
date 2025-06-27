/**
 * @description       : This class is responsible for processing loan conditions by sending documents and rules to an AI agent for validation.
 * @author            : Supriyo Seni
 * @group             : Queueable class
 * @last modified on  : 06-27-2025
 * @last modified by  : Supriyo Seni
**/
public class UptiqAIAgentCalloutQueueable implements Queueable, Database.AllowsCallouts{
    
    private FullSkope__Loan_Condition__c loanConditionObj;
    private List<String> storageIdList;

    /**
    * @description | Constructor to initialize the queueable with loan condition and storage IDs
    * @author Supriyo Seni | 06-27-2025 
    * @param loanConditionObj 
    * @param storageIdList 
    **/
    public UptiqAIAgentCalloutQueueable(FullSkope__Loan_Condition__c loanConditionObj, List<String> storageIdList) {
        this.loanConditionObj = loanConditionObj;
        this.storageIdList = storageIdList;
    }

    /**
    * @description | Executes the queueable job to send documents and rules to the AI agent for validation.
    * @author Supriyo Seni | 06-27-2025 
    * @param context 
    **/
    public void execute(QueueableContext context) {
        UptiqAIAgentCallout uptiqAIAgentCalloutInst = new UptiqAIAgentCallout();

        try {
            // Send documents and rules to the AI agent for validation
            uptiqAIAgentCalloutInst.initiateCallout(loanConditionObj, storageIdList);

        } catch (Exception excepInst) {
            // Handle timeout case by retrying via a queueable
            if (excepInst.getMessage().contains(UptiqAIConstants.READ_TIME_OUT) && uptiqAIAgentCalloutInst.transactionId != null) {
                Integer delayInMins = Integer.valueOf(Uptiq_AI_Rule_Engine__c.getInstance().Uptiq_Retry_Delay_In_Minutes__c ?? 5);
                System.enqueueJob(new UptiqAICalloutRetryQueueable(uptiqAIAgentCalloutInst.transactionId,loanConditionObj.Id),delayInMins);
            } else {
                // Log and notify for other errors
                Database.insert(UptiqAIUtil.createUptiqAIErrorLog( excepInst,UptiqAIAgentCalloutQueueable.class.getName(), new List<String>{loanConditionObj.Id}));
                UptiqAIUtil.sendFailureEmail(excepInst.getMessage());
            }
        }
    }
}
