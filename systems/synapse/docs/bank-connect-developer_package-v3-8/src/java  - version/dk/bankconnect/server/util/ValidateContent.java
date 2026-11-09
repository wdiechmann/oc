package dk.bankconnect.server.util;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;

import javax.xml.transform.Source;
import javax.xml.transform.stream.StreamSource;
import javax.xml.validation.Validator;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.w3c.dom.Document;
import org.w3c.dom.ls.LSResourceResolver;
import org.xml.sax.SAXParseException;

import com.google.common.io.ByteSource;
import com.google.common.io.Closeables;

import dk.bankconnect.common.io.ByteSources;
import dk.bankconnect.common.iso.iso20022.ISO20022CGIRuleVerification;
import dk.bankconnect.common.lang.Throwables;
import dk.bankconnect.common.w3c.dom.DocumentSource;
import dk.bankconnect.common.w3c.dom.Documents;
import dk.bankconnect.common.xml.validation.ISO20022ResourceResolver;
import dk.bankconnect.common.xml.validation.XMLValidator;

/**
 * Validation of content data.
 * 
 * @author Morten Sabroe Mortensen/BDYMMN
 */
public class ValidateContent
{
    private static final Log logger=LogFactory.getFactory().getInstance(ValidateContent.class);
    
    /**
     * 
     */
    public static DocumentSource createContentDocumentSource(String formatName,
                                                             String mimeType,
                                                             String characterEncoding,
                                                             String compressionName,
                                                             byte[] content,
                                                             Long contentDecompressionLimit)
         throws IOException
    {
        DocumentSource res=null;
        
        {
            Format format=Format.valueByName(formatName);
            
            if (format==null)
            {
                String message=
                    "Failure to create document source; "+
                    "cannot recognize format \""+formatName+"\"!";
                logger.warn(message);
            }
            else
            {
                Compression compression=Compression.valueByName(compressionName);
    
                if (compression==null)
                {
                    String message=
                        "Failure to create document source; "+
                        "cannot recognize format \""+formatName+"\"!";
                    logger.warn(message);
                }
                else
                {
                    ByteArrayInputStream contentStream=new ByteArrayInputStream(content); 
                    ByteSource compressedContent=ByteSources.createByteSource(contentStream);
                    
                    ByteSource decompressedContent=
                        compression.decompress(compressedContent,
                                               contentDecompressionLimit);
                    res=
                        format.createDocumentSource(mimeType,
                                                    characterEncoding,
                                                    decompressedContent);
                }
            }
        }
        
        return res;
    }

    /**
     * 
     * @param documentSource
     * @throws IOException
     */
    public static boolean validateContentByXMLSchema(DocumentSource documentSource) throws IOException
    {
        return validateContentByXMLSchema(documentSource,true);
    }
    
    /**
     * 
     * @param documentSource
     * @throws IOException
     */
    public static boolean validateContentByXMLSchema(DocumentSource documentSource,
                                                     boolean failOnError) throws IOException
    {
        boolean res=false;
        
        {
            if (documentSource==null)
            {
                String message=
                    "Failure to validate contents by XML Schema; "+
                    "the document source must be present!";
                throw new IllegalArgumentException(message);
            }
    
            SAXParseException validationError=null;
    
            //Set 'validationError':
            {
                InputStream documentStream=null;
    
                try
                {
                    documentStream=documentSource.getByteSource().openBufferedStream();
                    Source source=new StreamSource(documentStream);
                    
                    LSResourceResolver resourceResolver=new ISO20022ResourceResolver();
                    XMLValidator xmlValidator=new XMLValidator(resourceResolver);
            
                    try
                    {
                        Validator v=xmlValidator.createValidator();
                        v.validate(source);
                    }
                    catch (SAXParseException ex)
                    {
                        validationError=ex;
                    }
                    catch (Exception ex)
                    {
                        String message=
                            "Failure to verify XML content syntax by XML Schema!";
                        throw new RuntimeException(message);
                    }
                }
                finally
                {
                    Closeables.close(documentStream,true);
                }
            }
            
            if (validationError==null)  //if validation success ...
            {
                res=true;

                if (logger.isInfoEnabled())
                {
                    logger.info("Verified syntax of XML content by XML Schema, result is positive.");
                }
            }
            else
            {
                res=false;
                
                logger.warn("Verified syntax of XML content by XML Schema, result is negative; "+
                            "found error in line "+validationError.getLineNumber()+", column "+validationError.getColumnNumber()+
                            " with description \""+validationError.getMessage()+"\"!");
                
                if (!failOnError)
                {
                    logger.warn("No fail on error caused by XML Schema validation.");
                }
                else
                {
                    String message=
                        "Failure to verify syntax of XML content by XML Schema; "+
                        "found error in line "+validationError.getLineNumber()+", column "+validationError.getColumnNumber()+
                        " with description \""+validationError.getMessage()+"\"!";
                    throw new RuntimeException(message);
                }
            }
        }
        
        return res;
    }

    /**
     * 
     * @param documentSource
     * @throws IOException
     */
    public static boolean validateContentByCGIRules(DocumentSource documentSource) throws IOException
    {
        return validateContentByCGIRules(documentSource,true);
    }
    
    /**
     * 
     * @param documentSource
     * @throws IOException
     */
    public static boolean validateContentByCGIRules(DocumentSource documentSource,
                                                    boolean failOnError) throws IOException
    {
        boolean res=false;
        
        {
            if (documentSource==null)
            {
                String message=
                    "Failure to validate contents by CGI rules; "+
                    "the document source must be present!";
                throw new IllegalArgumentException(message);
            }
    
            Document document=documentSource.getDocument();
    
            ISO20022CGIRuleVerification ruleVerification=new ISO20022CGIRuleVerification();
            
            String namespaceURI=Documents.getNamespaceURI(document);
            boolean namespaceRecognized=ruleVerification.isNamespaceRecognized(document);
            
            if (!namespaceRecognized)
            {
                res=false;
                
                logger.warn("ISO 20022 CGI Rule verification skipped; "+
                            "the name space \""+namespaceURI+"\" of document cannot be recognized");
            }
            else
            {
                res=validateContentByCGIRules(document,ruleVerification,failOnError);
            }
        }
        
        return res;
    }

    /**
     * 
     * @param document
     * @param ruleVerification
     * @throws IOException
     */
    private static boolean validateContentByCGIRules(Document document,
                                                     ISO20022CGIRuleVerification ruleVerification,
                                                     boolean failOnError) throws IOException
    {
        boolean res=false;
        
        {
            if (document==null)
            {
                String message=
                    "Failure to validate contents by CGI rules; "+
                    "the document must be present!";
                throw new IllegalArgumentException(message);
            }
    
            IOException validationError=null;
            
            try
            {
                ruleVerification.verifyDocument(null,document);
            }
            catch (IOException ex)
            {
                validationError=ex;
            }
            
            if (validationError==null)  //if validation success ...
            {
                res=true;
                
                if (logger.isInfoEnabled())
                {
                    logger.info("Verified ISO 20022 CGI Rules, result is positive.");
                }
            }
            else
            {
                res=false;
                
                logger.warn(Throwables.appendMessageFromThrowable("Verified ISO 20022 CGI Rules, result is negative!",validationError));
                
                if (!failOnError)
                {
                    logger.warn("No fail on error caused by CGI Rules validation.");
                }
                else
                {
                    throw new IOException(validationError.getMessage(),validationError);  //Yes, really want a new exception and a copy of the message of the nested exception!
                }
            }
        }
        
        return res;
    }
}
