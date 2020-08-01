provider "aws" {
  region = "ap-south-1"
}

//Creating The Key and Saving them on The Disk

resource "tls_private_key" "mykey"{
	algorithm = "RSA"
}

resource "aws_key_pair" "key1" {
  key_name   = "key3"
  public_key = tls_private_key.mykey.public_key_openssh
}
 
resource "local_file" "key_pair_save"{
   content = tls_private_key.mykey.private_key_pem
   filename = "key.pem"
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//Creating The Security Group And Allowing The HTTP and SSH
resource "aws_security_group" "sec-grp" {

    depends_on = [
        tls_private_key.mykey,
        local_file.key_pair_save,
        aws_key_pair.key1
    ]
  name        = "Allowing SSH and HTTP"
  description = "Allow ssh & http connections"
 
  ingress {
    description = "Allowing Connection for SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allowing Connection For HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Connection for NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Web-Server"
  }
}


//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Launching EFS File System

resource "aws_efs_file_system" "myefs" {

  creation_token = "my-product"
  performance_mode = "generalPurpose"
  encrypted = "true"

  tags = {
    Name = "MyEFS"
  }
}

// Mounting The EFS


resource "aws_efs_mount_target" "alpha" {

  depends_on = [
    aws_efs_file_system.myefs,
    aws_security_group.sec-grp
  ]
  file_system_id = aws_efs_file_system.myefs.id
  security_groups = [aws_security_group.sec-grp.id]
  subnet_id = aws_instance.web1.subnet_id
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//Launching The Instances
    resource "aws_instance" "web1" {

        depends_on = [
            tls_private_key.mykey,
            aws_key_pair.key1,
            local_file.key_pair_save,
            aws_security_group.sec-grp,
        ]
        ami = "ami-0732b62d310b80e97"
        instance_type = "t2.micro"
        key_name = "key3"
        availability_zone = "ap-south-1a"
        security_groups = [aws_security_group.sec-grp.name]
        tags = {
        Name = "Web-Server"
              }
    }
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// Resource grp
  resource "null_resource" "null1"{
      depends_on = [
        aws_efs_mount_target.alpha,
        aws_instance.web1
      ]
    
        connection {
            type = "ssh"
            user = "ec2-user"
            private_key = tls_private_key.mykey.private_key_pem
            host = aws_instance.web1.public_ip
        }

        provisioner "remote-exec" {
            inline = [
               
                "sudo yum install httpd  php git amazon-efs-utils -y",
                "sudo systemctl start httpd",
                "sudo systemctl enable httpd",
                "sleep 90",
                "mkdir efs",
                "sudo  mount -t efs -o tls ${aws_efs_file_system.myefs.id}:/ /var/www/html",
                "sudo rm -rf /var/www/html/*",
                "sudo git clone https://github.com/ashutosh5786/for-ec2.git /var/www/html"
            ]
        
        }
    }
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Downlaod img The Images from The Github on local dir
resource "null_resource" "null2"{
  
    provisioner "local-exec" {
      command = "git clone https://github.com/ashutosh5786/for-ec2.git ./image"
    }

}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//Creating the S3 Bucket
resource "aws_s3_bucket" "my-s3" {
    bucket = "ashutosh-bucket-s3-for-task2"
    acl    = "public-read"
  

  tags = {
    Name        = "My bucket"
  }
}



//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Uplaoding File to Bucket
resource "aws_s3_bucket_object" "object" {
    depends_on = [
        null_resource.null2,
        aws_s3_bucket.my-s3
    ]
  bucket = aws_s3_bucket.my-s3.bucket
  key    = "img.png"
  source = "./image/12.png"
  acl = "public-read"
  }


// Delting the Image from local Directory
resource "null_resource" "null3"{
    depends_on = [
      aws_s3_bucket_object.object
    ]
    provisioner "local-exec" {
        
      command = "RMDIR /Q/S image"
    }

}

//Creating of The CLOUDFRONT


locals {
  s3_origin_id = "myS3Origin"
}


resource "aws_cloudfront_distribution" "distribution" {


    depends_on = [
        aws_s3_bucket.my-s3,

    ]
  origin {
    domain_name = aws_s3_bucket.my-s3.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "index.html"

  


  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  

  restrictions {
        geo_restriction {
            restriction_type = "none"
                        }
                  }


  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}



 
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Updating The URL in HTML file 


    resource "null_resource" "null4" {
        depends_on = [
            aws_cloudfront_distribution.distribution
        ]
            connection {
            type = "ssh"
            user = "ec2-user"
            private_key = tls_private_key.mykey.private_key_pem
            host = aws_instance.web1.public_ip
        }

        provisioner "remote-exec" {
            inline = [
                "cd /var/www/html",
                "sudo sed -i 's/12.png/https:${aws_cloudfront_distribution.distribution.domain_name}\\/img.png/g' index.html"
                ]
        
        }
    }


//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Opening the URL in Web-Browser
    resource "null_resource" "null5" {
        depends_on = [
            null_resource.null4
        ]

        provisioner "local-exec" {
            command = "chrome ${aws_instance.web1.public_ip}"
        
        }
    }


