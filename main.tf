########################################################
##  Developed By  :   Pradeepta Kumar Sahu
##  Project       :   Nasuni Kendra Integration
##  Organization  :   Nasuni - Labss   
#########################################################
##branch 330

data "aws_lambda_layer_version" "existing" {
  #layer_name = var.layer_name
   layer_name = "${var.layer_name}-${var.nacscheduler_uid}"
}

data "aws_s3_bucket" "discovery_source_bucket" {
  bucket = local.discovery_source_bucket
}
data "aws_secretsmanager_secret" "user_secrets" {
  name = var.user_secret
}
data "aws_secretsmanager_secret_version" "current_user_secrets" {
  secret_id = data.aws_secretsmanager_secret.user_secrets.id
}

locals {
  lambda_code_file_name_without_extension = "NAC_Discovery"
  lambda_code_extension                   = ".py"
  handler                                 = "lambda_handler"
  discovery_source_bucket                 = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.current_user_secrets.secret_string))["destination_bucket"]
  resource_name_prefix                    = "nasuni-labs"
  template_url                            = "https://s3.us-east-2.amazonaws.com/unifx-stack/unifx_s3_s3.yml"
  prams = merge(
    var.user_parameters,
    {
      ###################### Read input Parameters from TFVARS file #####################
      SourceBucketAccessKeyID = var.SourceBucketAccessKeyID != "" ? var.SourceBucketAccessKeyID : data.local_file.accZes.content
      SourceBucketSecretAccessKey = var.SourceBucketSecretAccessKey != "" ? var.SourceBucketSecretAccessKey : data.local_file.secRet.content
      DestinationBucketAccessKeyID = var.DestinationBucketAccessKeyID != "" ? var.DestinationBucketAccessKeyID : data.local_file.accZes.content
      DestinationBucketSecretAccessKey = var.DestinationBucketSecretAccessKey != "" ? var.DestinationBucketSecretAccessKey : data.local_file.secRet.content

      ###################### Read input Parameters from Secret Manager #####################
      ProductKey          = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.current_user_secrets.secret_string))["nac_product_key"]
      VolumeKeyParameter  = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.current_user_secrets.secret_string))["volume_key"]
      VolumeKeyPassphrase = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.current_user_secrets.secret_string))["volume_key_passphrase"]
      DestinationBucket   = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.current_user_secrets.secret_string))["destination_bucket"]

      ###################### Read input Parameters from NMC API #####################
      UniFSTOCHandle = data.local_file.toc.content
      SourceBucket   = data.local_file.bkt.content

      # Read input Parameters from Parameter Store
      /* VolumeKeyPassphrase               = jsondecode(data.aws_ssm_parameter.volume_data.*.value)
      /* VolumeKeyPassphrase               = nonsensitive(jsondecode(jsonencode(data.aws_ssm_parameter.volume_data.value))) */
      ############# Hard coding Parameters ##########################################    
      StartingPoint        = var.StartingPoint
      IncludeFilterPattern = var.IncludeFilterPattern
      IncludeFilterType    = var.IncludeFilterType
      ExcludeFilterPattern = var.ExcludeFilterPattern
      ExcludeFilterType    = var.ExcludeFilterType
      MinFileSizeFilter    = var.MinFileSizeFilter
      MaxFileSizeFilter    = var.MaxFileSizeFilter
      PrevUniFSTOCHandle   = var.PrevUniFSTOCHandle
      DestinationPrefix    = "/nasuni-labs/${var.volume_name}/${data.local_file.toc.content}"
      MaxInvocations       = var.MaxInvocations
    },
  )
}
resource "random_id" "nac_unique_stack_id" {
  byte_length = 6
}
resource "aws_cloudformation_stack" "nac_stack" {
  count = module.this.enabled ? 1 : 0

  name          = "nasuni-labs-NasuniAnalyticsConnector-${random_id.nac_unique_stack_id.hex}"
  tags          = module.this.tags
  template_url  = local.template_url
  # template_body = file("${path.cwd}/nac-cf.template.yaml")
  /* template_url       = "https://s3.us-east-2.amazonaws.com/unifx-stack/unifx_s3_s3.yml" */
  parameters         = local.prams
  capabilities       = var.capabilities
  on_failure         = var.on_failure
  timeout_in_minutes = var.timeout_in_minutes
  policy_body        = var.policy_body
  depends_on = [data.local_file.accZes,
    data.local_file.secRet,
    aws_lambda_function.lambda_function,
    aws_secretsmanager_secret_version.internal_secret_u
  ]
}

################### START - NAC Discovery Lambda ####################################################
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "nac-discovery-py/"
  output_path = "${local.lambda_code_file_name_without_extension}.zip"
}

resource "aws_lambda_function" "lambda_function" {
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "${local.lambda_code_file_name_without_extension}.${local.handler}"
  runtime          = var.runtime
  filename         = "${local.lambda_code_file_name_without_extension}.zip"
  function_name    = "${local.resource_name_prefix}-${local.lambda_code_file_name_without_extension}-Lambda-${random_id.nac_unique_stack_id.hex}"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 600 
  layers           = [data.aws_lambda_layer_version.existing.arn] 
  tags = {
    Name            = "${local.resource_name_prefix}-${local.lambda_code_file_name_without_extension}-Lambda-${random_id.nac_unique_stack_id.hex}"
    Application     = "Nasuni Analytics Connector with Kendra"
    Developer       = "Nasuni"
    PublicationType = "Nasuni Labs"
    Version         = "V 0.1"
  }
  depends_on = [
    aws_iam_role_policy_attachment.lambda_logging,
    aws_iam_role_policy_attachment.s3_GetObject_access,
    aws_iam_role_policy_attachment.KendraHttpPost_access,
    aws_iam_role_policy_attachment.GetSecretValue_access,
    aws_cloudwatch_log_group.lambda_log_group,
    data.local_file.accZes,
    data.local_file.secRet,
    data.local_file.v_guid,
    data.local_file.bkt,
    data.local_file.toc,
  ]

}


########################################## Internal Secret  ########################################################
data "aws_secretsmanager_secret" "admin_secret_kendra" {
  name = var.admin_secret_kendra
}
data "aws_secretsmanager_secret_version" "admin_secret_kendra" {
  secret_id = data.aws_secretsmanager_secret.admin_secret_kendra.id
}

resource "aws_secretsmanager_secret" "internal_secret_u" {
  name        = "nasuni-labs-internal-${random_id.nac_unique_stack_id.hex}"
  description = "Nasuni Analytics Connector's version specific internal secret. This will be created as well as destroyed along with NAC."
}
resource "aws_secretsmanager_secret_version" "internal_secret_u" {
  secret_id     = aws_secretsmanager_secret.internal_secret_u.id
  secret_string = jsonencode(local.secret_data_to_update)
  depends_on = [
    aws_iam_role.lambda_exec_role,
    aws_lambda_function.lambda_function,
  ]
}


locals {
  secret_data_to_update = {
    # last-run = timestamp()
    root_handle               = data.local_file.toc.content
    discovery_source_bucket   = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.current_user_secrets.secret_string))["destination_bucket"]
    # es_url                    = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.admin_secret_kendra.secret_string))["nac_es_url"]
    nac_stack                 = "nasuni-labs-NasuniAnalyticsConnector-${random_id.nac_unique_stack_id.hex}"
    discovery_lambda_role_arn = aws_iam_role.lambda_exec_role.arn
    discovery_lambda_name     = aws_lambda_function.lambda_function.function_name
    aws_region                = var.region
    user_secret_name          = var.user_secret
    volume_name               = var.volume_name
    # web_access_appliance_address	= jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.current_user_secrets.secret_string))["web_access_appliance_address"]
    web_access_appliance_address = data.local_file.appliance_address.content
    destination_prefix           = "/nasuni-labs/${var.volume_name}/${data.local_file.toc.content}"
  }
}


resource "aws_iam_role" "lambda_exec_role" {
  name        = "${local.resource_name_prefix}-lambda_exec_role-${local.lambda_code_file_name_without_extension}-${random_id.nac_unique_stack_id.hex}"
  path        = "/"
  description = "Allows Lambda Function to call AWS services on your behalf."

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "kendra.amazonaws.com"
        },
     "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = {
    Name            = "${local.resource_name_prefix}-lambda_exec-${local.lambda_code_file_name_without_extension}-${random_id.nac_unique_stack_id.hex}"
    Application     = "Nasuni Analytics Connector with Kendra"
    Developer       = "Nasuni"
    PublicationType = "Nasuni Labs"
    Version         = "V 0.1"
  }
}

############## CloudWatch Integration for Lambda ######################
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${local.resource_name_prefix}-${local.lambda_code_file_name_without_extension}-${random_id.nac_unique_stack_id.hex}"
  retention_in_days = 14

  tags = {
    Name            = "${local.resource_name_prefix}-lambda_log_group-${local.lambda_code_file_name_without_extension}-${random_id.nac_unique_stack_id.hex}"
    Application     = "Nasuni Analytics Connector with Kendra"
    Developer       = "Nasuni"
    PublicationType = "Nasuni Labs"
    Version         = "V 0.1"
  }
}

# AWS Lambda Basic Execution Role
resource "aws_iam_policy" "lambda_logging" {
  name        = "${local.resource_name_prefix}-lambda_logging_policy-${local.lambda_code_file_name_without_extension}-${random_id.nac_unique_stack_id.hex}"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
  tags = {
    Name            = "${local.resource_name_prefix}-lambda_logging_policy-${local.lambda_code_file_name_without_extension}-${random_id.nac_unique_stack_id.hex}"
    Application     = "Nasuni Analytics Connector with Kendra"
    Developer       = "Nasuni"
    PublicationType = "Nasuni Labs"
    Version         = "V 0.1"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

############## IAM policy for accessing S3 from a lambda ######################
resource "aws_iam_policy" "s3_GetObject_access" {
  name        = "${local.resource_name_prefix}-s3_GetObject_access_policy-${local.lambda_code_file_name_without_extension}-${random_id.nac_unique_stack_id.hex}"
  path        = "/"
  description = "IAM policy for accessing S3 from a lambda"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::*"
        }
    ]
}
EOF
  tags = {
    Name            = "${local.resource_name_prefix}-s3_GetObject_access_policy-${local.lambda_code_file_name_without_extension}-${random_id.nac_unique_stack_id.hex}"
    Application     = "Nasuni Analytics Connector with Kendra"
    Developer       = "Nasuni"
    PublicationType = "Nasuni Labs"
    Version         = "V 0.1"
  }

}

resource "aws_iam_role_policy_attachment" "s3_GetObject_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.s3_GetObject_access.arn
}

############## IAM policy for accessing Kendra Domain from a lambda ######################


resource "aws_iam_policy" "kendra_data_load" {
  name        = "${local.resource_name_prefix}-data_load_policy-${random_id.nac_unique_stack_id.hex}"
  path        = "/"
  description = "IAM policy for data loading to Kendra"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "kendra:BatchPutDocument",
                "kendra:BatchDeleteDocument"
            ],
            "Resource": "*"
        }
    ]
}
EOF
  tags = {
    Name            = "${local.resource_name_prefix}-data_load_policy-${local.lambda_code_file_name_without_extension}-${random_id.nac_unique_stack_id.hex}"
    Application     = "Nasuni Analytics Connector with Kendra"
    Developer       = "Nasuni"
    PublicationType = "Nasuni Labs"
    Version         = "V 0.1"
  }
}

resource "aws_iam_role_policy_attachment" "KendraHttpPost_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.kendra_data_load.arn
}
############## IAM policy for accessing Secret Manager from a lambda ######################
resource "aws_iam_policy" "GetSecretValue_access" {
  name        = "${local.resource_name_prefix}-GetSecretValue_access_policy-${local.lambda_code_file_name_without_extension}-${random_id.nac_unique_stack_id.hex}"
  path        = "/"
  description = "IAM policy for accessing secretmanager from a lambda"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "secretsmanager:GetSecretValue",
            "Resource": "${data.aws_secretsmanager_secret.user_secrets.arn}"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": "secretsmanager:GetSecretValue",
            "Resource": "${aws_secretsmanager_secret.internal_secret_u.arn}"
        },
        {
            "Sid": "VisualEditor2",
            "Effect": "Allow",
            "Action": "secretsmanager:GetSecretValue",
            "Resource": "${data.aws_secretsmanager_secret.admin_secret_kendra.arn}"
        }
    ]
}
EOF
  tags = {
    Name            = "${local.resource_name_prefix}-GetSecretValue_access_policy-${local.lambda_code_file_name_without_extension}-${random_id.nac_unique_stack_id.hex}"
    Application     = "Nasuni Analytics Connector with Kendra"
    Developer       = "Nasuni"
    PublicationType = "Nasuni Labs"
    Version         = "V 0.1"
  }
}

resource "aws_iam_role_policy_attachment" "GetSecretValue_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.GetSecretValue_access.arn
}

################################### Attaching AWS Managed IAM Policies ##############################################################

data "aws_iam_policy" "CloudWatchFullAccess" {
  arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_iam_role_policy_attachment" "CloudWatchFullAccess" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = data.aws_iam_policy.CloudWatchFullAccess.arn
}

data "aws_iam_policy" "AWSLambdaVPCAccessExecutionRole" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "AWSLambdaVPCAccessExecutionRole" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = data.aws_iam_policy.AWSLambdaVPCAccessExecutionRole.arn
}

data "aws_iam_policy" "AWSCloudFormationFullAccess" {
  arn = "arn:aws:iam::aws:policy/AWSCloudFormationFullAccess"
}

resource "aws_iam_role_policy_attachment" "AWSCloudFormationFullAccess" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = data.aws_iam_policy.AWSCloudFormationFullAccess.arn
}

data "aws_iam_policy" "AmazonS3FullAccess" {
  arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "AmazonS3FullAccess" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = data.aws_iam_policy.AmazonS3FullAccess.arn
}

data "aws_iam_policy" "AmazonEC2FullAccess" {
  arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "AmazonEC2FullAccess" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = data.aws_iam_policy.AmazonEC2FullAccess.arn
}

data "aws_iam_policy" "AmazonKENDRAFullAccess" {
  arn = "arn:aws:iam::aws:policy/AmazonKendraFullAccess"
}

resource "aws_iam_role_policy_attachment" "AmazonKENDRAFullAccess" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = data.aws_iam_policy.AmazonKENDRAFullAccess.arn
}

################# Trigger Lambda Function on S3 Event ######################
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.arn
  principal     = "s3.amazonaws.com"
  source_arn    = data.aws_s3_bucket.discovery_source_bucket.arn

  depends_on = [aws_lambda_function.lambda_function]
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = data.aws_s3_bucket.discovery_source_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_function.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ""
  }
  depends_on = [aws_lambda_permission.allow_bucket]
}


################################################# END LAMBDA########################################################
resource "random_id" "r_id" {
  byte_length = 1
}
data "local_file" "secRet" {
  filename   = "${path.cwd}/Zsecret_${random_id.nac_unique_stack_id.hex}.txt"
  depends_on = [null_resource.nmc_api_data]

}

data "local_file" "accZes" {
  filename   = "${path.cwd}/Zaccess_${random_id.nac_unique_stack_id.hex}.txt"
  depends_on = [null_resource.nmc_api_data]
}

############################## NMC API CALL ###############################

locals {
  nmc_api_endpoint             = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.current_user_secrets.secret_string))["nmc_api_endpoint"]
  nmc_api_username             = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.current_user_secrets.secret_string))["nmc_api_username"]
  nmc_api_password             = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.current_user_secrets.secret_string))["nmc_api_password"]
  web_access_appliance_address = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.current_user_secrets.secret_string))["web_access_appliance_address"]

}

resource "null_resource" "nmc_api_data" {
  provisioner "local-exec" {
    command = "python3 fetch_volume_data_from_nmc_api.py ${local.nmc_api_endpoint} ${local.nmc_api_username} ${local.nmc_api_password} ${var.volume_name} ${random_id.nac_unique_stack_id.hex} ${local.web_access_appliance_address} && echo 'nasuni-labs-internal-${random_id.nac_unique_stack_id.hex}' > nac_uniqui_id.txt"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "rm -rf *.txt"
  }
}

data "local_file" "toc" {
  filename   = "${path.cwd}/nmc_api_data_root_handle_${random_id.nac_unique_stack_id.hex}.txt"
  depends_on = [null_resource.nmc_api_data]
}


output "latest_toc_handle_processed" {
  value      = data.local_file.toc.content
  depends_on = [data.local_file.toc]
}

data "local_file" "bkt" {
  filename   = "${path.cwd}/nmc_api_data_source_bucket_${random_id.nac_unique_stack_id.hex}.txt"
  depends_on = [null_resource.nmc_api_data]
}


output "source_bucket" {
  value      = data.local_file.bkt.content
  depends_on = [data.local_file.bkt]
}

data "local_file" "v_guid" {
  filename   = "${path.cwd}/nmc_api_data_v_guid_${random_id.nac_unique_stack_id.hex}.txt"
  depends_on = [null_resource.nmc_api_data]
}


output "volume_guid" {
  value      = data.local_file.v_guid.content
  depends_on = [data.local_file.v_guid]
}


data "local_file" "appliance_address" {
  filename   = "${path.cwd}/nmc_api_data_external_share_url_${random_id.nac_unique_stack_id.hex}.txt"
  depends_on = [null_resource.nmc_api_data]
}


output "appliance_address" {
  value      = data.local_file.appliance_address.content
  depends_on = [data.local_file.appliance_address]
}



resource "local_file" "Lambda_Name" {
  content    = aws_lambda_function.lambda_function.function_name
  filename   = "Lambda_Name.txt"
  depends_on = [aws_lambda_function.lambda_function]
}
############################################################################
