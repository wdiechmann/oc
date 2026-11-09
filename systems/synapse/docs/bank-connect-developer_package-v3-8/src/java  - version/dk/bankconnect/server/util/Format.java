package dk.bankconnect.server.util;

import java.io.IOException;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import com.google.common.io.ByteSource;

import dk.bankconnect.common.w3c.dom.DocumentSource;

/**
 * Format of content data recognized.
 * 
 * @author Morten Sabroe Mortensen/BDYMMN
 */
public enum Format
{
    ISO_20022(new String[]{"ISO20022","ISO 20022"},
              new MIMEType[]{MIMEType.ApplicationXML,MIMEType.TextXML});
  
    Format(String[] names,
           MIMEType[] mimeTypes)
    {
        this.names=Collections.unmodifiableList(Arrays.asList(names));
        this.mimeTypes=Collections.unmodifiableList(Arrays.asList(mimeTypes));
    }

    private List<String> names;
    private List<MIMEType> mimeTypes;
  
    public String getName()
    {
        return names.get(0);
    }
  
    public List<String> getNames()
    {
        return names;
    }
  
    public MIMEType getMIMEType()
    {
        return mimeTypes.get(0);
    }
  
    public List<MIMEType> getMIMETypes()
    {
        return mimeTypes;
    }
  
    public DocumentSource createDocumentSource(String mimeType,
                                               String characterEncoding,
                                               ByteSource content)
        throws IOException
    {
        DocumentSource res=null;
      
        {
            MIMEType _mimeType=MIMEType.valueByName(mimeType);
            
            if (_mimeType==null)
            {
              String message=
                  "Failure to create document source; "+
                  "cannot recognize the MIME-type \""+mimeType+"\"!";
              throw new IOException(message);
            }

            res=_mimeType.createDocumentSource(characterEncoding,content);
        }
      
        return res;
    }
    
    public static Format valueByName(String name)
    {
        Format res=null;
        
        {
            if (name!=null)
            {
                Format[] values=Format.values();
                for (Format value: values)
                {
                    if (value.names.contains(name))
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
