type EmailReceiver = {
  name: string
  emailAddress: string
}

@description('Name of the Azure Monitor Action Group.')
param actionGroupName string

@description('Email receivers for the Action Group.')
param emailReceivers EmailReceiver[]

// groupShortName must be <= 12 chars; use a deterministic, compact form.
var groupShortName = take(replace(actionGroupName, '-', ''), 12)

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  properties: {
    groupShortName: groupShortName
    enabled: true
    emailReceivers: [for r in emailReceivers: {
      name: r.name
      emailAddress: r.emailAddress
      useCommonAlertSchema: true
    }]
  }
}
