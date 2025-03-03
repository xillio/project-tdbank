param(
    $type = $args[0],
    $Global:DatabaseName = "Vault",
    $Global:CollectionName = "encryptedData",
    # Encryption settings
    $Global:key = "your256bitsecretkeyyour256bitsec",     # 32-byte key for AES-256
    $Global:iv = "randomIV12345678"     # 16-byte IV for AES
)
##################################################
# script that inserts masked encrypted values into MongoDB
# 
##################################################
# Required module for MongoDB
#Install-Module -Name Mdbc -Force (If you don't have Mdbc installed)


function decrypt(){
    # Required module for MongoDB
# Install-Module -Name Mdbc -Force (If you don't have Mdbc installed)

# Prompt for the ID
$ID = Read-Host "Enter the Name (ID) to retrieve and decrypt the value"

# Convert key and IV to byte arrays
$keyBytes = [System.Text.Encoding]::UTF8.GetBytes($key)
$ivBytes = [System.Text.Encoding]::UTF8.GetBytes($iv)

# MongoDB connection settings

try {
    # Retrieve the document with the given ID
    $Query = @{ "_id" = $ID }
    $Collection = MongoConnect;
    $Document = Get-MdbcData -Filter $Query -Collection $Collection

    if ($null -eq $Document) {
        Write-Error "No document found with ID: $ID"
        exit
    }

    # Extract the encrypted value
    $EncryptedValue = $Document.EncryptedValue
    Write-Host "Encrypted Value: $EncryptedValue" -ForegroundColor Yellow

    # Decrypt the value
    $encryptedBytes = [Convert]::FromBase64String($EncryptedValue)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $keyBytes
    $aes.IV = $ivBytes

    $decryptor = $aes.CreateDecryptor()
    $decryptedBytes = $decryptor.TransformFinalBlock($encryptedBytes, 0, $encryptedBytes.Length)
    $DecryptedValue = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)

    Write-Host "Decrypted Value: $DecryptedValue" -ForegroundColor Green

} catch {
    Write-Error "An error occurred: $_"
} 
}
function encrypt(){
    # Prompt for inputs
    $Name = Get-SecureInput -Prompt "Enter the Name (ID)"
    $Value = Get-SecureInput -Prompt "Enter the Value to encrypt"

    # Convert key and IV to byte arrays
    $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($key)
    $ivBytes = [System.Text.Encoding]::UTF8.GetBytes($iv)

    # Encrypt the value
    try {
        # Create AES encryption object
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes
        $aes.IV = $ivBytes

        # Convert the value to byte array
        $valueBytes = [System.Text.Encoding]::UTF8.GetBytes($Value)

        # Perform encryption
        $encryptor = $aes.CreateEncryptor()
        $encryptedBytes = $encryptor.TransformFinalBlock($valueBytes, 0, $valueBytes.Length)
        $EncryptedValue = [Convert]::ToBase64String($encryptedBytes)

        Write-Host "Value encrypted successfully."
    } catch {
        Write-Error "Encryption failed: $_"
        exit
    }
    # Document to insert
    $Document = @{
        _id = $Name
        EncryptedValue = $EncryptedValue
    }

    # Insert into MongoDB
    try {
        $Collection = MongoConnect;
        # Insert the document
        $Collection.InsertOne($Document)
        Write-Host "Document successfully written to MongoDB." -ForegroundColor Green
    }catch {
        Write-Error "MongoDB could not write document: $_"
    }
}
function Get-SecureInput {
    param (
        [string]$Prompt = "Enter input"
    )

    # Display the prompt
    Write-Host "$($Prompt): " -NoNewline

    # Input buffers
    $inputBuffer = @()
    $maskBuffer = ""

    # Timing
    $lastKeyTime = Get-Date

    while ($true) {
        # Check for key press
        if ([System.Console]::KeyAvailable) {
            $key = [System.Console]::ReadKey($true)

            # Handle Enter key (to finish input)
            if ($key.Key -eq "Enter") {
                Write-Host ""  # Move to the next line
                break
            }

            # Handle Backspace
            if ($key.Key -eq "Backspace" -and $inputBuffer.Count -gt 0) {
                $inputBuffer = $inputBuffer[0..($inputBuffer.Count - 2)] # Remove last character
                $maskBuffer = "*" * $inputBuffer.Count
                Write-Host "`b `b" -NoNewline # Remove the last character from the display
            } elseif ($key.Key -ne "Backspace") {
                # Add the typed character to the input buffer
                $inputBuffer += $key.KeyChar
                Write-Host $key.KeyChar -NoNewline
                $lastKeyTime = Get-Date
            }
        }

        # Mask characters after 0.5 seconds of inactivity
        if (((Get-Date) - $lastKeyTime).TotalSeconds -ge 0.5 -and $maskBuffer.Length -lt $inputBuffer.Count) {
            $maskBuffer = "*" * $inputBuffer.Count
            Write-Host "`r$($Prompt): $maskBuffer" -NoNewline
        }
    }

    # Return the collected input as a string
    return -join $inputBuffer
}
function MongoConnect{
    # Insert into MongoDB
    try {
        # Import the Mdbc module
        Import-Module Mdbc -ErrorAction Stop

        # Connect to MongoDB
        $MongoUrl = "mongodb://$($MongoServer):$MongoPort"
        $MongoClient = Connect-Mdbc $MongoUrl

        # Select the database and collection
        $Database = Get-MdbcDatabase -Name $DatabaseName -Client $MongoClient
        $Collection = Get-MdbcCollection -Name $CollectionName -Database $Database
    }catch {
        Write-Error "MongoDB connect: $_"
    } 
    return $Collection
}

write-host "Encryption/Decryption into Vault MongoDb"
write-host "********************************************************"

if( (Get-Module -ListAvailable -Name Mdbc).count -eq 0 ){
    write-host -ForegroundColor Red "   NOT found Mdbc module";
    exit;
}else{
  # write-host "   Found Mdbc";
}


if(Test-Path -Path "./config.json"){
    $Config = Get-Content -Path "./config.json" | ConvertFrom-Json
    $Global:MongoServer = $Config.MongoServer
    $Global:MongoPort = $Config.MongoPort

}else{
    write-host -ForegroundColor Red "Could not find Mongo config.json for data."
    exit;
}


if($type -eq 'encrypt'){
    encrypt
}elseif ($type -eq 'decrypt'){
    decrypt
}else{
    write-host 'No usable action given. Use encrypt or decrypt'

}
write-host "********************************************************"
write-host "Completed."
exit