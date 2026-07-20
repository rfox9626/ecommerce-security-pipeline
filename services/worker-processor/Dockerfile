FROM public.ecr.aws/lambda/python:3.11

# Set the working directory to the standard Lambda task location
WORKDIR /var/task

# Copy and install dependencies
COPY requirements.txt ./
RUN pip install -r requirements.txt

# Copy your application code
COPY app.py ./

CMD [ "app.lambda_handler" ]
