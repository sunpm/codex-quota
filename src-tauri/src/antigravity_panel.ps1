$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$scope = [System.Windows.Automation.TreeScope]::Descendants
$ae = [System.Windows.Automation.AutomationElement]
$ct = [System.Windows.Automation.ControlType]
$ariaRole = [System.Windows.Automation.AutomationProperty]::LookupById(30101)
$headingLevel = [System.Windows.Automation.AutomationProperty]::LookupById(30173)
$anchor = [System.Windows.Automation.AndCondition]::new(
    [System.Windows.Automation.PropertyCondition]::new($ae::ControlTypeProperty, $ct::Button),
    [System.Windows.Automation.PropertyCondition]::new($ae::NameProperty, 'Refresh quota and credits data'))

function Read-Section($element, $items) {
    $type = $element.Current.ControlType
    $role = if ($ariaRole) { $element.GetCurrentPropertyValue($ariaRole) }
    $level = if ($headingLevel) { $element.GetCurrentPropertyValue($headingLevel) }
    if ($role -eq 'heading' -or $level -in (80051..80059) -or $element.Current.LocalizedControlType -in @('heading','标题')) {
        $name = $element.Current.Name
        if (!$name) {
            $label = $element.FindFirst($scope, [System.Windows.Automation.PropertyCondition]::new($ae::ControlTypeProperty, $ct::Text))
            if ($label) { $name = $label.Current.Name }
        }
        if ($name) { $items.Add(@{ heading = $name }) }
        return
    }
    if ($type -eq $ct::Text) {
        $name = $element.Current.Name
        if ($name) { $items.Add(@{ text = $name }) }
        return
    }
    if ($type -notin @($ct::Group, $ct::Pane, $ct::List, $ct::ListItem, $ct::Custom)) { return }
    for ($child = $walker.GetFirstChild($element); $null -ne $child; $child = $walker.GetNextSibling($child)) {
        Read-Section $child $items
    }
}

foreach ($app in (Get-Process -Name Antigravity -ErrorAction SilentlyContinue)) {
    if ($app.MainWindowHandle -eq 0) { continue }
    $windows = $ae::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.PropertyCondition]::new($ae::ProcessIdProperty, [int]$app.Id))
    $button = $null
    foreach ($window in $windows) {
        $button = $window.FindFirst($scope, $anchor)
        if ($button) { break }
    }
    if ($null -eq $button) { continue }
    for ($node = $button; $null -ne $node; $node = $walker.GetParent($node)) {
        if ($node.Current.ControlType -in @($ct::Document, $ct::Window)) { break }
        $items = [System.Collections.Generic.List[object]]::new()
        for ($next = $walker.GetNextSibling($node); $null -ne $next; $next = $walker.GetNextSibling($next)) {
            Read-Section $next $items
        }
        if ($items.Where({ $_.ContainsKey('heading') }).Count) {
            [Console]::Write((ConvertTo-Json -InputObject $items.ToArray() -Compress))
            exit 0
        }
    }
    [Console]::Write('[]')
    exit 0
}
exit 2
