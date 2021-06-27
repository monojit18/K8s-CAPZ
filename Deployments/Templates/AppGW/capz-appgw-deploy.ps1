param([Parameter(Mandatory=$false)] [string] $rg,
      [Parameter(Mandatory=$false)] [string] $fpath,
      [Parameter(Mandatory=$false)] [string] $deployFileName,
      [Parameter(Mandatory=$false)] [string] $vnetName,
      [Parameter(Mandatory=$false)] [string] $subnetName,
      [Parameter(Mandatory=$false)] [string] $appgwName,
      [Parameter(Mandatory=$false)] [array]  $httpsListenerNames,
      [Parameter(Mandatory=$false)] [string] $listenerHostName,
      [Parameter(Mandatory=$false)] [string] $backendPoolHostName,
      [Parameter(Mandatory=$false)] [string] $backendIpAddress,      
      [Parameter(Mandatory=$false)] [string] $healthProbeHostName,
      [Parameter(Mandatory=$false)] [string] $healthProbePath)

Test-AzResourceGroupDeployment -ResourceGroupName $rg `
-TemplateFile "$fpath/AppGW/$deployFileName.json" `
-TemplateParameterFile "$fpath/AppGW/$deployFileName.parameters.json" `
-applicationGatewayName $appgwName `
-vnetName $vnetName -subnetName $subnetName `
-httpsListenerNames $httpsListenerNames `
-listenerHostName $listenerHostName `
-backendPoolHostName $backendPoolHostName `
-backendIpAddress $backendIpAddress `
-healthProbeHostName $healthProbeHostName `
-healthProbePath $healthProbePath

New-AzResourceGroupDeployment -ResourceGroupName $rg `
-TemplateFile "$fpath/AppGW/$deployFileName.json" `
-TemplateParameterFile "$fpath/AppGW/$deployFileName.parameters.json" `
-applicationGatewayName $appgwName `
-vnetName $vnetName -subnetName $subnetName `
-httpsListenerNames $httpsListenerNames `
-listenerHostName $listenerHostName `
-backendPoolHostName $backendPoolHostName `
-backendIpAddress $backendIpAddress `
-healthProbeHostName $healthProbeHostName `
-healthProbePath $healthProbePath