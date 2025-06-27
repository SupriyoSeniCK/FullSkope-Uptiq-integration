/**
 * @description       : This class contains the utility methods for Uptiq AI Signed URL Controller Apex class.
 * @author            : Supriyo Seni
 * @group             : Controller class
 * @last modified on  : 06-26-2025
 * @last modified by  : Supriyo Seni
**/
public inherited sharing class UptiqAISignedURLController {

    /**
    * @description | Method to generate the signed URL for uploading documents to Uptiq storage
    * @author Supriyo Seni | 06-13-2025 
    * @param documentCount - Number of documents for which signed URLs are to be generated
    * @return List<UptiqAISignedURLResponseParser> - List of parsed responses containing signed URLs and metadata
    **/
    public static List<UptiqAISignedURLResponseParser> getUptiqSignedUrls(Integer documentCount){

        // Get Uptiq Storage Path
        String uptiqStoragePath = Uptiq_AI_Rule_Engine__c.getInstance().Uptiq_AI_Storage_Path__c;

        // Initialize response list
        List<UptiqAISignedURLResponseParser> signedUrlParserList = new List<UptiqAISignedURLResponseParser>();
        
        // Prepare request payload
        StorageResponseParser storageResponseParserInst = new StorageResponseParser();
        storageResponseParserInst.count = documentCount;
        storageResponseParserInst.storagePath = uptiqStoragePath;
        
        // Setup HTTP callout
        Http httpInst = new Http();
        HttpRequest requestInst = new HttpRequest();
        requestInst.setEndpoint(UptiqAIConstants.UPTIQ_SIGNED_URL_CALLOUT_CREDENTIAL);
        requestInst.setMethod(UptiqAIConstants.POST);
        requestInst.setBody(Json.serialize(storageResponseParserInst));
        requestInst.setHeader(UptiqAIConstants.CONTENT_TYPE, UptiqAIConstants.APPLICATION_JSON);
        
        // Send request and deserialize the response
        HttpResponse responseInst = httpInst.send(requestInst);
        signedUrlParserList = (List<UptiqAISignedURLResponseParser>)JSON.deserialize(responseInst.getBody(), List<UptiqAISignedURLResponseParser>.class);
        
        return signedUrlParserList;
    }

    /**
    * @description | Method to upload a document to Uptiq Storage and return the associated storage ID
    * @author Supriyo Seni | 06-18-2025 
    * @param loanConditionId - ID of the related loan condition
    * @param versionObj - ContentVersion object representing the document
    * @param signedURLInst - Signed URL metadata for the document
    * @return String - Storage ID returned after successful upload
    **/
    public static String getUptiqStorageId(Id loanConditionId, ContentVersion versionObj, UptiqAISignedURLResponseParser signedURLInst){

        // Track heap size
        Integer heapUsed = Limits.getHeapSize();
        Integer heapLimit = Limits.getLimitHeapSize();

        // Check if adding the blob would exceed 12 MB heap and less than 36 MB Limit, if so redirect file upload using EmailService because it can handle larger files upto 36 MB
        if (heapUsed  >= heapLimit && heapUsed < heapLimit*3) {
            // Set up the email object
            Messaging.SingleEmailMessage mailObj = new Messaging.SingleEmailMessage();
            mailObj.setToAddresses(new List<String>{Uptiq_AI_Rule_Engine__c.getInstance().File_Upload_Service_Email_Address__c});
            mailObj.setPlainTextBody(signedURLInst.signedUrl + UptiqAIConstants.UNIQUE_STRING + versionObj.Id);
            // Send the email
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mailObj });
            return null;
        }else if (heapUsed >= heapLimit*3){
            // Throw exception if the document size is greater than 36 MB
            throw new CustomException('Document size exceeds the allowed limit (36 MB) for processing. Document Id :' + versionObj.Id);
        }
        // Prepare PUT request to upload the document using the signed URL
        HttpRequest requestInst = new HttpRequest();
        requestInst.setEndpoint(signedURLInst.signedUrl);
        requestInst.setMethod(UptiqAIConstants.PUT);
        requestInst.setHeader(UptiqAIConstants.CONTENT_TYPE, UptiqAIConstants.APPLICATION_OCTET_STREAM);
        requestInst.setBodyAsBlob(versionObj.VersionData);
        
        // Execute callout
        Http httpObj = new Http();
        HTTPResponse responseObj = httpObj.send(requestInst);
        
        // Throw exception if upload fails
        if(responseObj.getStatusCode() != 200){
            throw new CustomException('Error in uploading document to Uptiq Storage for Loan Condition :  ' + loanConditionId );
        }

        // Return storage ID on success
        return signedURLInst.storageId;
    }

    /**
    * @description | This class is used to parse the response from the signed URL generation callout.
    **/
    public class UptiqAISignedURLResponseParser {
        public String storageId;   // Unique ID for the stored document in Uptiq system
        public String documentId;  // External reference or document identifier
        public String signedUrl;   // Pre-signed URL for uploading the document
        public String key;         // Key associated with the document in the storage
    }

    /**
    * @description | This class is used to prepare the request payload for generating signed URLs
    **/
    public class StorageResponseParser {
        public Integer count;         // Number of signed URLs requested
        public String storagePath;    // Path in the storage where files will be uploaded
    }
}