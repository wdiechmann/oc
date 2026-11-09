<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
	xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

	<xsl:output method="html" />
	<xsl:template match="/">
		<html>
            <meta charset="utf-8"/>
            <meta http-equiv="X-UA-Compatible" content="IE=edge"/>
            <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
            <header>
                <link rel="stylesheet" href="http://netdna.bootstrapcdn.com/bootstrap/3.0.3/css/bootstrap.min.css"/>
            </header>
            <style>
                html,body { height:100%; }
                #wrap {
                min-height: 100%;
                height: auto;
                margin: 0 auto -60px;
                padding: 0 0 60px;
                }

                #footer {
                height: 60px;
                background-color: #f5f5f5;
                }
                .container {
                width: auto;
                max-width: 1080px;
                padding: 0 15px;
                }
                .container .text-muted {
                margin: 20px 0;
                }
            </style>

			<body>
                <div id="wrap">
                    <div class="container">
                        <div class="page-header">
                            <h1>ISO20022</h1>
                        </div>
                        <p class="lead">Her vises indholdet af PAIN 002 xml filen.</p>
                        
                        
                        
						<!--GRUPPE INFORMATION. START -->
					

                        <div class="panel panel-default">
                            <div class="panel-heading"><h4>Gruppe</h4></div>
                            <div class="panel-body">
                                <div class="row"  >
                                    <div class="col-md-4"><b>Leverance nøgle(MsgId)</b></div>
                                    <div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrPmtStsRpt']/*[name()='GrpHdr']/*[name()='MsgId']/text()" /></div>
                                    
                                </div>
                                <div class="row">
                                    <div class="col-md-4"><b>Dannnelse af fil(CreDtTm)</b></div>
                                    <div class="col-md-4">
                                        <xsl:variable name="date">
                                            <xsl:value-of select="/*[name()='Document']/*[name()='CstmrPmtStsRpt']/*[name()='GrpHdr']/*[name()='CreDtTm']/text()"  />
                                        </xsl:variable>
                                          <xsl:value-of select="concat(substring($date,0,5),'-', substring($date,6,2),'-', substring($date,9,2))"/>
                                    </div>
                                </div>
                                 <div class="row"  >
                                    <div class="col-md-4"><b>Kundens id</b></div>
                                    <div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrPmtStsRpt']/*[name()='GrpHdr']/*[name()='InitgPty']/*[name()='Id']/*[name()='OrgId']/*[name()='Othr']/*[name()='Id']/text()" /></div>
                                </div>
                                
                            </div>
                        </div>
                        
                        
                       	<!--GRUPPE INFORMATION. SLUT -->
                       	
             
                        
                        <!--PAYMENT INFORMATION. START -->
                        
                        <div class="panel panel-default">
                            <div class="panel-heading"><h4></h4></div>
                            <div class="panel-body">
                             	 <div class="row"  >
                             		   	<div class="col-md-4"><b>Leverancenøgle fra Pain 001(OrgnlMsgId)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrPmtStsRpt']/*[name()='OrgnlGrpInfAndSts']/*[name()='OrgnlMsgId']/text()" /></div>
                             	  </div>
                             	   <div class="row"  >
                             		   	<div class="col-md-4"><b>Betalingsoprindelse(OrgnlMsgNmId)</b></div>
                             	 	  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrPmtStsRpt']/*[name()='OrgnlGrpInfAndSts']/*[name()='OrgnlMsgNmId']/text()" /></div>
                            	   </div>
                             	   <div class="row"  >
                             		   	<div class="col-md-4"><b>Leverance status(GrpSts)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrPmtStsRpt']/*[name()='OrgnlGrpInfAndSts']/*[name()='GrpSts']/text()" /></div>
                             	  </div>
                        	 </div>      
                       </div>       
                        
                      <!--PAYMENT INFORMATION. SLUT -->
              
                        
                      <!--PAYMENT RECORDS. START -->  
       				
       				 <xsl:for-each select="/*[name()='Document']/*[name()='CstmrPmtStsRpt']/*[name()='OrgnlPmtInfAndSts']">
       				 
       				 	<xsl:variable name="OrgnlPmtInfId">
                        	<xsl:value-of select="*[name()='OrgnlPmtInfId']/text()" />
                      	</xsl:variable>
                      
                      	<xsl:variable name="PmtInfSts">
                        	<xsl:value-of select="*[name()='PmtInfSts']/text()" />
                      	</xsl:variable>
                      	
                      	<xsl:variable name="AddtlInf">
                        	<xsl:value-of select="*[name()='StsRsnInf']/*[name()='AddtlInf']/text()" />
                      	</xsl:variable>
                      
                      
                      
                    
       				
                   		 <table class="table table-bordered">
                        	<thead>
                                                  
                            	<xsl:if test="$OrgnlPmtInfId and (string($OrgnlPmtInfId))">
                             	  	<th>Unik debetnøgle(OrgnlPmtInfId)</th>
                             	</xsl:if>
                             	                   
                            	<xsl:if test="$PmtInfSts and (string($PmtInfSts))">
                             	  	<th>Betalingsstatus(PmtInfSts)</th>
                             	</xsl:if>
                             	
                             	<xsl:if test="$AddtlInf and (string($AddtlInf))">
                             	  	<th>Udvidet vejlinfo om betaling(AddtlInf)</th>
                             	</xsl:if>
                             	
                        	</thead>
                        
                        	<tbody>
                           
                             	<tr>
                              		<xsl:if test="($OrgnlPmtInfId) and (string($OrgnlPmtInfId))">
                             		 		<td> <xsl:value-of select="$OrgnlPmtInfId"/> </td>
                             		</xsl:if>
                             		<xsl:if test="($PmtInfSts) and (string($PmtInfSts))">
                             		 		<td> <xsl:value-of select="$PmtInfSts"/> </td>
                             		</xsl:if>
                             		<xsl:if test="($AddtlInf) and (string($AddtlInf))">
                             		 		<td> <xsl:value-of select="$AddtlInf"/> </td>
                             		</xsl:if>
                             		
                             		
                                </tr>
                            
                            </tbody>
                    
                    	</table>
                    
                    </xsl:for-each>
                    
                    
                     <!--PAYMENT RECORDS. SLUT -->  
                    
                    </div>
                </div>

                <div id="footer">
                    <div class="container">
                        <p class="text-muted">(c) BankConnect 2014</p>
                    </div>
                </div>

            </body>
		</html>
	</xsl:template>

</xsl:stylesheet>
