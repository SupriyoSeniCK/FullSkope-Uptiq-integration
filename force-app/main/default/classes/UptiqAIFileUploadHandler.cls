/**
 * @description       : Handles inbound emails to process file uploads using signed URLs.
 *                      This class extracts data from the email body, fetches the related ContentVersion,
 *                      and performs a callout to upload the file to an external storage service.
 * @author            : Supriyo Seni
 * @group             : Uptiq AI Integration
 * @last modified on  : 06-26-2025
 * @last modified by  : Supriyo Seni
**/
public without sharing class UptiqAIFileUploadHandler implements Messaging.InboundEmailHandler {

    /**
     * @description Handles incoming email, extracts a signed URL and ContentVersion ID from the email body,
     *              retrieves the ContentVersion, and uploads the file to the external storage via HTTP PUT.
     *              Logs errors and sends notification emails on failure.
     *
     * @param emailInst      Incoming email instance containing plain text body.
     * @param envelopeInst   Envelope containing email metadata (not used in current logic).
     * @return Messaging.InboundEmailResult indicating success or failure of processing.
     */
    public Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail emailInst, Messaging.InboundEnvelope envelopeInst) {
        Messaging.InboundEmailResult resultInst = new Messaging.InboundEmailResult();
        String emailPlainText = emailInst.plainTextBody;

        try {
            // Extract signed URL and ContentVersion Id from email (assumed format: signedUrl@#documentId)
            List<String> calloutParamList = emailPlainText.split(UptiqAIConstants.UNIQUE_STRING);

            // Validate email format
            if (calloutParamList.size() != 2) {
                throw new CustomException('Invalid email format. Expected format: signedUrl@#documentId');
            }

            // Fetch the ContentVersion record based on the provided ID
            List<ContentVersion> contentVersionList = [SELECT Id, 
                                                                VersionData
                                                        FROM ContentVersion
                                                        WHERE Id = :calloutParamList[1]
                                                        WITH SYSTEM_MODE];

            if (contentVersionList.isEmpty()) {
                throw new CustomException('ContentVersion not found for Id: ' + calloutParamList[1]);
            }

            // Prepare HTTP PUT request using signed URL
            HttpRequest requestInst = new HttpRequest();
            requestInst.setEndpoint(calloutParamList[0]);
            requestInst.setMethod(UptiqAIConstants.PUT);
            requestInst.setHeader(UptiqAIConstants.CONTENT_TYPE, UptiqAIConstants.APPLICATION_OCTET_STREAM);
            requestInst.setBodyAsBlob(contentVersionList[0].VersionData);

            // Execute callout to external storage
            Http httpObj = new Http();
            HttpResponse responseInst = httpObj.send(requestInst);

            // Validate callout response
            if (responseInst.getStatusCode() != 200) {
                throw new CustomException('Error in uploading document to Uptiq Storage for ContentVersion: ' + calloutParamList[1]);
            }

        } catch (Exception excepInst) {
            // Log the exception and send failure notification
            Database.insert(UptiqAIUtil.createUptiqAIErrorLog(excepInst, UptiqAIFileUploadHandler.class.getName(), null));
            UptiqAIUtil.sendFailureEmail(excepInst.getMessage());
        }

        resultInst.success = true;
        return resultInst;
    }
}