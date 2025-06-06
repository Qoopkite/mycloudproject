###########################################################
# 1. Data Source (Ubuntu 22.04 AMI 조회)
############################################################
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]             # Ubuntu 공식 퍼블리셔(099720109477)
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

############################################################
# 2. VPC / Subnet / Internet Gateway(IGW) / Route Table
############################################################
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "mycloudproject-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags = {
    Name = "mycloudproject-public-subnet"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}c"
  tags = {
    Name = "mycloudproject-public-subnet-2"
  }
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "mycloudproject-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "mycloudproject-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

############################################################
# 3. Security Group 설정
############################################################
# 3-1. EC2용 Security Group (SSH, HTTP, 앱 포트(3000) 허용)
resource "aws_security_group" "ec2_sg" {
  name        = "mycloudproject-ec2-sg"
  description = "Allow SSH, HTTP(80), App(3000) from anywhere"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # SSH (추후 본인 IP로 제한 권장)
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # HTTP
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # 애플리케이션 포트
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mycloudproject-ec2-sg"
  }
}

# 3-2. RDS용 Security Group (EC2 SG에서만 접속 허용)
resource "aws_security_group" "rds_sg" {
  name        = "mycloudproject-rds-sg"
  description = "Allow MySQL from EC2 SG only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mycloudproject-rds-sg"
  }
}

############################################################
# 4. IAM Role & Instance Profile (EC2에 부여할 권한)
############################################################
# 4-1. IAM Role 생성 (EC2에 부여될 Role)
resource "aws_iam_role" "ec2_role" {
  name = "mycloudproject-ec2-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# 4-2. IAM Policy (CloudWatch Logs 쓰기, 시스템 메트릭 전송 권한)
data "aws_iam_policy_document" "cw_agent_policy" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cw_agent_policy" {
  name   = "mycloudproject-cw-agent-policy"
  policy = data.aws_iam_policy_document.cw_agent_policy.json
}

# 4-3. Role에 Policy 연결
resource "aws_iam_role_policy_attachment" "attach_cw_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.cw_agent_policy.arn
}

# 4-4. IAM Instance Profile 생성 (EC2에 Role을 붙이기 위한 중간 객체)
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "mycloudproject-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

############################################################
# 5. EC2 인스턴스 생성 (Ubuntu 22.04, Node.js 앱 실행, CloudWatch Agent 설치)
############################################################
resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id       # Ubuntu 22.04 AMI 사용
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = aws_subnet.public.id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
              #!/bin/bash
              # (Ubuntu에서는 apt-get 사용)
              
              # 1) Node.js, git, PM2 설치 (Ubuntu 22.04 기준)
              apt-get update -y
              apt-get install -y curl software-properties-common
              curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
              apt-get install -y nodejs git
              npm install -g pm2

              # 2) 애플리케이션 코드 클론 및 실행
              cd /home/ubuntu
              git https://github.com/Qoopkite/mycloudproject.git
              cd mycloudproject/app
              npm install
              pm2 start index.js --name myapp

              # 3) CloudWatch Agent 설치 및 설정 (Ubuntu 예시)
              apt-get install -y amazon-cloudwatch-agent
               (cloudwatch-config.json 내용은 infra 코드에서 별도로 정의)
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config \
                -m ec2 -c file:/home/ubuntu/mycloudproject/app/src/cloudwatch-config.json -s
              EOF

  tags = {
    Name = "mycloudproject-app-server"
  }
}

############################################################
# 6. RDS 인스턴스 생성 (MySQL)
############################################################
resource "aws_db_subnet_group" "main" {
  name       = "mycloudproject-db-subnet-group"
  subnet_ids = [aws_subnet.public.id, aws_subnet.public_2.id]
  tags = {
    Name = "mycloudproject-db-subnet-group"
  }
}

resource "aws_db_instance" "app_db" {
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  name                 = "appdb"
  username             = var.db_username
  password             = var.db_password
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.main.name
  publicly_accessible  = false
  tags = {
    Name = "mycloudproject-rds"
  }
}

############################################################
# 7. CloudWatch Dashboard 정의
############################################################
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "mycloudproject-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      # 7-1. EC2 CPU Utilization 차트
      {
        type  = "metric"
        x     = 0
        y     = 0
        width = 6
        height= 6
        properties = {
          view          = "timeSeries"
          metrics       = [
            [ "AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.app_server.id ]
          ]
          region        = var.aws_region
          stat          = "Average"
          period        = 300
          title         = "EC2 CPU Utilization"
        }
      },
      # 7-2. RDS CPU Utilization 차트
      {
        type  = "metric"
        x     = 6
        y     = 0
        width = 6
        height= 6
        properties = {
          view          = "timeSeries"
          metrics       = [
            [ "AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.app_db.id ]
          ]
          region        = var.aws_region
          stat          = "Average"
          period        = 300
          title         = "RDS CPU Utilization"
        }
      }
      # 7-3. 추가 위젯 예시 (Memory, DB Connections 등) → 주석 처리됨
    ]
  })
}
