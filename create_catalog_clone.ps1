#Requires -Version 5.1
#
# PowerShell Script: 1C Catalog "Surgical Injection"
# Author: Gemini, Senior 1C DevOps Engineer
# Description: Clones a 1C Catalog object ("Предметы" -> "УТО_Тест") within a hierarchical XML configuration dump.
# The script is idempotent and adheres to 1C v8.3.25 XML structure rules.
#

param(
    [string]$ProjectBasePath = "1c-test-xml-7",
    [string]$DonorType = "Catalog",
    [string]$DonorName = "Предметы",
    [string]$CloneName = "УТО_Тест"
)

# --- Configuration & Helper Functions ---
$ErrorActionPreference = 'Stop'
$nl = [System.Environment]::NewLine

# Define full names for easier reference
$DonorFullName = "$($DonorType)s.$DonorName"
$CloneFullName = "$($DonorType)s.$CloneName"
$DonorFileName = "$DonorName.xml"
$CloneFileName = "$CloneName.xml"

# Define paths
$CatalogsPath = Join-Path -Path $ProjectBasePath -ChildPath "Catalogs"
$DonorFilePath = Join-Path -Path $CatalogsPath -ChildPath $DonorFileName
$CloneFilePath = Join-Path -Path $CatalogsPath -ChildPath $CloneFileName

$ConfigXmlPath = Join-Path -Path $ProjectBasePath -ChildPath "Configuration.xml"
$ConfigDumpInfoXmlPath = Join-Path -Path $ProjectBasePath -ChildPath "ConfigDumpInfo.xml"

# Function to create a new UUID
function New-Uuid {
    return ([System.Guid]::NewGuid().ToString())
}

# --- Main Execution Logic ---
Write-Host "--- 1C Metadata Surgical Injection Started ---"
Write-Host "Project Path: $ProjectBasePath"
Write-Host "Cloning '$DonorFullName' to '$CloneFullName'" -ForegroundColor Yellow

# --- Step 1: Idempotency - Clean up existing artifacts ---
Write-Host $nl"Step 1: Cleaning up previous artifacts (Idempotency)..."

# Remove clone file if it exists
if (Test-Path $CloneFilePath) {
    Remove-Item $CloneFilePath -Force
    Write-Host "  - Removed existing file: $CloneFilePath"
}

# Remove from Configuration.xml
$configXml = [xml](Get-Content -Path $ConfigXmlPath -Raw)
$childObjectNode = $configXml.Configuration.ChildObjects.SelectSingleNode("//*[. = '$($DonorType).$CloneName']")
if ($null -ne $childObjectNode) {
    $childObjectNode.ParentNode.RemoveChild($childObjectNode)
    $configXml.Save($ConfigXmlPath)
    Write-Host "  - Removed entry from Configuration.xml"
}

# Remove from ConfigDumpInfo.xml
$configDumpXml = [xml](Get-Content -Path $ConfigDumpInfoXmlPath -Raw)
$metadataNode = $configDumpXml.ConfigDumpInfo.ChildObjects.SelectSingleNode("//Metadata[. = '$($DonorType).$CloneName']")
if ($null -ne $metadataNode) {
    $metadataNode.ParentNode.RemoveChild($metadataNode)
    $configDumpXml.Save($ConfigDumpInfoXmlPath)
    Write-Host "  - Removed entry from ConfigDumpInfo.xml"
}
Write-Host "Cleanup complete." -ForegroundColor Green

# --- Step 2: Genetic Cloning - Create new object from donor ---
Write-Host $nl"Step 2: Cloning donor file and replacing identifiers..."
if (-not(Test-Path $DonorFilePath)) {
    throw "Donor file not found at '$DonorFilePath'"
}

$rawContent = Get-Content -Path $DonorFilePath -Raw
# Using -creplace for case-sensitive replacement
$newContent = $rawContent -creplace "\.$DonorName", ".$CloneName"
$newContent = $newContent -creplace ">$DonorName<", ">$CloneName<"

Write-Host "Identifier replacement complete." -ForegroundColor Green

# --- Step 3: UUID Regeneration (8.3.25 format) ---
Write-Host $nl"Step 3: Regenerating UUIDs for the new object..."
$cloneXml = [xml]$newContent

# Set new root UUID
$cloneXml.MetaDataObject.FirstChild.SetAttribute("uuid", (New-Uuid))
Write-Host "  - Assigned new root UUID."

# Set new TypeId and ValueId UUIDs
$typeNodes = $cloneXml.SelectNodes("//xr:TypeId", $cloneXml.NamespaceManager)
$valueNodes = $cloneXml.SelectNodes("//xr:ValueId", $cloneXml.NamespaceManager)

if (($null -eq $typeNodes) -or ($null -eq $valueNodes)) {
    throw "Could not find TypeId/ValueId nodes. Check XML namespaces."
}

$typeNodes | ForEach-Object { $_.InnerText = (New-Uuid) }
$valueNodes | ForEach-Object { $_.InnerText = (New-Uuid) }

$uuidCount = $typeNodes.Count + $valueNodes.Count
Write-Host "  - Regenerated $uuidCount internal Type/Value UUIDs."

# Save the new catalog XML file
if (-not(Test-Path $CatalogsPath)) {
    New-Item -ItemType Directory -Path $CatalogsPath | Out-Null
}
# Save with UTF-8 encoding and standard XML header
$writer = [System.IO.StreamWriter]::new($CloneFilePath, $false, [System.Text.Encoding]::UTF8)
$cloneXml.Save($writer)
$writer.Close()
Write-Host "New catalog file saved to '$CloneFilePath'." -ForegroundColor Green

# --- Step 4: Topological Integration ---
Write-Host $nl"Step 4: Integrating new object into configuration topology..."

# 4.1: Integrate into Configuration.xml
$configXml = [xml](Get-Content -Path $ConfigXmlPath -Raw)
$configChildObjects = $configXml.Configuration.ChildObjects
$lastCatalogNode = $configChildObjects.SelectNodes("Catalog") | Select-Object -Last 1

$newCatalogNode = $configXml.CreateElement("Catalog", $configXml.DocumentElement.NamespaceURI)
$newCatalogNode.InnerText = "$($DonorType).$CloneName"

if ($null -ne $lastCatalogNode) {
    [void]$configChildObjects.InsertAfter($newCatalogNode, $lastCatalogNode)
    Write-Host "  - Injected into Configuration.xml after last Catalog."
} else {
    # If no catalogs exist, find the last node of the previous type (e.g., Form, CommonModule)
    # For this example, we'll just append it if no other catalogs are found.
    [void]$configChildObjects.AppendChild($newCatalogNode)
    Write-Host "  - Appended to Configuration.xml (no existing Catalogs found)."
}
$configXml.Save($ConfigXmlPath)

# 4.2: Integrate into ConfigDumpInfo.xml
$configDumpXml = [xml](Get-Content -Path $ConfigDumpInfoXmlPath -Raw)
$dumpChildObjects = $configDumpXml.ConfigDumpInfo.ChildObjects
$lastCatalogDumpNode = $dumpChildObjects.SelectNodes("Metadata[starts-with(., 'Catalog.')]") | Select-Object -Last 1

$newMetadataNode = $configDumpXml.CreateElement("Metadata", $configDumpXml.DocumentElement.NamespaceURI)
$newMetadataNode.InnerText = "$($DonorType).$CloneName"

if ($null -ne $lastCatalogDumpNode) {
    [void]$dumpChildObjects.InsertAfter($newMetadataNode, $lastCatalogDumpNode)
    Write-Host "  - Injected into ConfigDumpInfo.xml after last Catalog entry."
} else {
    [void]$dumpChildObjects.AppendChild($newMetadataNode)
     Write-Host "  - Appended to ConfigDumpInfo.xml (no existing Catalog entries found)."
}
$configDumpXml.Save($ConfigDumpInfoXmlPath)

Write-Host "Integration complete." -ForegroundColor Green
Write-Host $nl"--- Surgical Injection Successful ---"
Write-Host "You can now run /LoadConfigFromFiles to apply changes." -ForegroundColor Cyan
