## Makefile for building and deploying Lambda functions
#
# grab aws config information from the command line tool (aws)
ifndef SHELL
SHELL = /bin/bash
endif
ifndef AWS
AWS = aws
endif
AWS_ACCESS_KEY_ID = $(shell $(AWS) configure get aws_access_key_id)
AWS_SECRET_ACCESS_KEY = $(shell $(AWS) configure get aws_secret_access_key)
LAMBDA_REGION = $(shell $(AWS) configure get region)
LAMBDA_ENV_VARS_RESERVED = AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
#
# We use environment variables to transmit configuration info (typically 'secrets')
# LAMBDA_ENV_VARS_SECRET enumerates these
# LAMBDA_ENV_VARS_RESERVED are AWS specific ones needed to communicate the configs to the docker environment, 
# 	but these are not needed in the actual deployment since they are automatically set by Lambda
LAMBDA_ENVS_TEST = $(foreach envvar,$(LAMBDA_ENV_VARS_RESERVED) $(LAMBDA_ENV_VARS_SECRET),-e $(envvar)="$($(envvar))")
LAMBDA_ENVS_DEPLOY = Variables='{$(foreach envvar,$(LAMBDA_ENV_VARS_SECRET),$(envvar)="$($(envvar))",)}'

# enumerate all the targets
.PHONY: all
all: 
	@echo "Available targets are:"
	@echo "	task - builds a 'task' subdirectory that emulates the lambda environment"
	@echo "	task.zip - builds task.zip - the package to be deployed to lambda
	@echo "	test - tests the lambda function"
	@echo "	deploy - builds task.zip from 'task' above, and deploys it to AWS as a new lambda function"
	@echo "	updates - updates the AWS lambda function created via 'deploy'"
	@echo "	clean - removes the task subdir and task.zip file"

# task directory effectively contains the package for the Lambda function.
# this rule builds the directory, installing all the needed packages via docker
task:
	mkdir task
	echo "yum -y install python-pip" > task/setup.sh
	for pkg in $(LAMBDA_PKGS); do echo "pip install -t . $$pkg" >> task/setup.sh ; done
	docker run -v $(shell pwd)/task:/var/task -it --rm lambci/lambda:build-$(LAMBDA_RUNTIME) bash setup.sh

# LAMBDA_FILES list all the files that needs to go into the package (i.e., the task directory)
$(addprefix task/, $(LAMBDA_FILES)) : task/%: % task
	cp $< $@

# use docker to run a test scenario
.PHONY: test
test: $(addprefix task/, $(LAMBDA_FILES))
	docker run -v $(shell pwd)/task:/var/task $(LAMBDA_ENVS_TEST) lambci/lambda:$(LAMBDA_RUNTIME) $(LAMBDA_HANDLER) $(LAMBDA_TEST_EVENT)

# task.zip is the package to be deployed
# this can be uploaded via the AWS console as well
task.zip: $(addprefix task/, $(LAMBDA_FILES))
	cd task; zip -ur ../task.zip *

# use aws commandline to deploy task.zip to the lambda function
.PHONY: deploy
deploy: task.zip
	$(AWS) lambda create-function \
		--zip-file fileb://task.zip \
		--region $(LAMBDA_REGION) \
		--function-name $(LAMBDA_FUNC_NAME) \
		--role $(LAMBDA_ROLE) \
		--environment $(LAMBDA_ENVS_DEPLOY) \
		--vpc-config $(LAMBDA_VPC_CONFIG) \
		--handler $(LAMBDA_HANDLER) \
		--timeout $(LAMBDA_TIMEOUT) \
		--runtime $(LAMBDA_RUNTIME)

# use aws commandline to update the lambda function
.PHONY: update
update: task.zip
	$(AWS) lambda update-function-code \
		--zip-file fileb://task.zip \
		--function-name $(LAMBDA_FUNC_NAME)

.PHONY: clean
clean:
	rm -rf task task.zip

# this runs an interactive shell in the docker environment
.PHONY: docker
docker: $(addprefix task/, $(LAMBDA_FILE))
	docker run -v $(shell pwd)/task:/var/task -it --rm lambci/lambda:build-$(LAMBDA_RUNTIME) bash


