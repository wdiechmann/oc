package dk.bankconnect.server.util;

import com.google.common.base.Charsets;
import com.google.common.io.ByteSource;

import dk.bankconnect.common.w3c.dom.DocumentSource;

/**
 * MIME types of content data recognized.
 * 
 * @author Morten Sabroe Mortensen/BDYMMN
 */
public enum MIMEType
{
    ApplicationXML("application/xml",true,false),
    TextXML("text/xml",false,true),
    PEM("application/x-pem-file",false,true);
  
    MIMEType(String name,
             boolean canReadContentAsXMLBinary,
             boolean canReadContentAsXMLTextually)
    {
        this.name=name;
        this.canReadContentAsXMLBinary=canReadContentAsXMLBinary;
        this.canReadContentAsXMLTextually=canReadContentAsXMLTextually;
    }

    private String name;
    private boolean canReadContentAsXMLBinary;
    private boolean canReadContentAsXMLTextually;
  
    public String getName()
    {
        return name;
    }
  
    public DocumentSource createDocumentSource(String characterEncoding,
                                               ByteSource content)
    {
        DocumentSource res=null;
      
        {
            if (canReadContentAsXMLBinary)
            {
                if (characterEncoding!=null && !characterEncoding.isEmpty())
                {
                    String message=
                        "Failure to create document source; "+
                        "cannot process character encoding \""+characterEncoding+"\"!";
                    throw new IllegalStateException(message);
                }
              
                res=new DocumentSource(content);
            }
            else
            {
                if (canReadContentAsXMLTextually)
                {
                    if (characterEncoding==null || characterEncoding.isEmpty())
                    {
                        characterEncoding=Charsets.US_ASCII.name();
                    }
                  
                    res=new DocumentSource(content,characterEncoding);
                }
                else
                {
                    res=null;  //Yes, can not create a document source!
                }
            }
        }
      
        return res;
    }
  
    public static MIMEType valueByName(String name)
    {
        MIMEType res=null;
        
        {
            if (name!=null)
            {
                MIMEType[] values=MIMEType.values();
                for (MIMEType value: values)
                {
                    if (name.equals(value.getName()))
                    {
                        res=value;
                        break;
                    }
                }
            }
        }
        
        return res;
    }
}
