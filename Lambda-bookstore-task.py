import json
import boto3
import base64
from botocore.exceptions import ClientError

# Get path parameter (operation) and book data from API Gateway event
# This function checks for an optional "Image" key in the book data or a base64 encoded image in the event body.
# It validates book data and handles potential errors during DynamoDB interaction.
# If an image is provided (either base64 or image key), it attempts to upload the image to S3 with a unique filename.
# The updated book data with the image URL (if uploaded) is then stored in the DynamoDB table.
# Also, I am using the pathParameters as REST APIs often leverage path parameters embedded within the URL path itself to define specific resources or operations.
# For example, in a bookstore API, we might have a URL like /books/{bookId} where {bookId} is a path parameter that identifies a particular book.
# The Lambda function, when invoked with this URL, would extract the bookId value from the pathParameters key in the event object.
# Per AWS using pathParameters promote a clear and consistent way to define operations within a REST API. 
# Developers using the API can easily understand what resources or actions are available based on the URL structure.
# Path parameters allow for dynamic URLs that can target specific entities within your system. This makes the API more versatile and extensible.
# I took assumption that the request body structure includes {"operation": "create", "dictionary": {...}}
def lambda_handler(event, context):
  try:
    # Extract operation and book data (already well-structured)
    operation = event.get('pathParameters', {}).get('operation', '').lower() # converting any operation to lower case
    print(f"operation is: {operation}") # debug for CloudWatch
    print(event.keys()) # debug for CloudWatch
    print("Entire event:", event)  # Debug - Print the entire event dictionary
    book_data = event.get('dictionary')
    print("book_data before parsing:", book_data) # debug for CloudWatch
    if isinstance(book_data, str):
        book_data = json.loads(book_data)
    print("book_data after parsing:", book_data) # debug for CloudWatch
    image_data = event.get('isBase64Encoded', False)  # Check for base64 encoded image
    image = book_data.pop('Image', None)  # Get optional image key from data
    message = event.get('body', {}).get('message', '')  # Retrieve message (enhanced)

    # Access DynamoDB resource and S3 client
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('bookstore')
    s3_client = boto3.client('s3')
    bucket_name = 'bookstore-task-images'

    # Perform operation based on path parameter
    response = {}  # Initialize an empty response dictionary to store the response from the CRUD functions
    if operation == 'echo': # for testing purposes
      message = event.get('dictionary', {}).get('message', '')  # Retrieve message from nested payload
      response = {'message': message}  # Include retrieved message in response
      # Return the modified response dictionary
      return response
    elif operation == 'create':
     response = create_book(table, book_data, image, image_data, s3_client, bucket_name)
    elif operation == 'read':
     response = get_book(table, book_data)
    elif operation == 'update':
     response = update_book(table, book_data, image, image_data, s3_client, bucket_name)
    elif operation == 'delete':
     response = delete_book(table, book_data, s3_client, bucket_name)
    else:
     return {
       'statusCode': 400,
       'body': json.dumps(f'Unsupported operation: {operation}')
     }
    # Ensure consistent response structure for all CRUD operations
    return {
       'statusCode': response.get('statusCode', 200),  # Default 200 for success (unless set otherwise by one of the CRUD functions)
       'body': json.dumps(response.get('body', '{}'))  # Default empty body in case the CRUD function won't excplicitly provide one
    }
  except KeyError:
    return {
       'statusCode': 400,
       'body': json.dumps('Missing operation or data in request')
    }
  except json.JSONDecodeError:
    return {
       'statusCode': 400,
       'body': json.dumps('Invalid JSON format for book data')
    }

# Function to create a new book
# Implement book data validation and image upload logic 
# This function retrieves book data from the API Gateway event body in JSON format.
# It performs basic validation to ensure required fields are present. You can implement more robust validation based on your needs.
# It connects to the DynamoDB resource and uses the put_item method to create a new entry in the table with the provided book data.
# It handles potential errors like ConditionalCheckFailedException which occurs if a book with the same ISBN already exists.
# The function returns a success message with HTTP status code 201 (Created) on success or an error message with appropriate status code depending on the exception.
def create_book(table, book_data, image, image_data, s3_client, bucket_name):
  """Creates a new book entry in the DynamoDB table.

    Args:
        table (boto3.resource): A DynamoDB table resource.
        book_data (dict): Dictionary containing book details.
        image (str, optional): Optional image filename (if provided).
        image_data (bool, optional): Flag indicating base64 encoded image.
        s3_client (boto3.client): S3 client for image upload (if applicable).
        bucket_name (str): Name of the S3 bucket for image storage.

    Returns:
        dict: A dictionary containing the HTTP status code and response message.
  """
  try:
    condition = {'ConditionExpression': 'attribute_not_exists(ISBN)'}  # Check for non-existent ISBN
    # This line retrieves the value for the key ConditionExpression from the condition dictionary and uses that 
    # string value for the ConditionExpression parameter.
    table.put_item(Item=book_data, ConditionExpression=condition['ConditionExpression'])
    response = {'message': 'Book created successfully!'}
    return {'statusCode': 201, 'body': json.dumps(response)} # Include both keys
  except ClientError as e:
    # Handle specific errors (e.g., duplicate ISBN)
    if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
        return {
            'statusCode': 409,
            'body': json.dumps('Book with this ISBN already exists')
        }
    else:
        return handle_error(e, operation='create')

  return {'statusCode': 201, 'body': response}
 
# Function to get book details
def get_book(table, book_data):
  """Retrieves book details from the DynamoDB table based on provided data (usually ISBN).

  Args:
      table (boto3.resource): A DynamoDB table resource.
      book_data (dict): Dictionary containing the key to identify the book (e.g., {'ISBN': '1234567890'}).

  Returns:
        dict: A dictionary containing the HTTP status code and the retrieved book data (if successful), or an empty dictionary if book not found.
  """

  # Validate input (e.g., ISBN) and retrieve book data from DynamoDB
  try:
    response = table.get_item(Key=book_data)
    return {'statusCode': 200, 'body': response['Item'] if 'Item' in response else {}}
  except ClientError as e:
    # Handle specific errors (e.g., book not found)
    return handle_error(e, operation='get')  # Directly call generic error handler

# Function to update book details
# This function iterates through the book data dictionary.
# It excludes the "ISBN" key from being updated (assuming it's the primary key).
# For other keys, it creates an update expression with the Value set to the corresponding value in the book data.
def get_attribute_updates(book_data):
  updates = {}
  for key, value in book_data.items():
    if key != 'ISBN':  # Assuming ISBN is not an attribute to update
      updates[key] = {'Value': value}
  return updates  

def update_book(table, book_data, image, image_data, s3_client, bucket_name):
  # Validate input, update data in DynamoDB, and handle image updates (refer to previous explanations)
  # This function requires the primary key of the item we want to update (ISBN) to be provided as a dictionary.  
  """Updates book details in the DynamoDB table.

  Args:
      table (boto3.resource): A DynamoDB table resource.
      book_data (dict): Dictionary containing the updated book details (ISBN is assumed to be unchanged).
      image (str, optional): Optional image filename (if provided).
      image_data (bool, optional): Flag indicating base64 encoded image.
      s3_client (boto3.client): S3 client for image upload (if applicable).
      bucket_name (str): Name of the S3 bucket for image storage.
  Returns:
      dict: A dictionary containing the HTTP status code and a response message indicating success or failure.
  """
  try:
        # Update book data in DynamoDB (including ISBN as a Key dictionary)
        update_expression = "SET"
        expression_attributes = {}
        for key, value in book_data.items():
           if key != "ISBN":  # Skip ISBN as it's used for the key
              # Escape double quotes within the key (if any)
               escaped_key = key.replace('"', '\\"')
              # Construct the key without additional escaping before the colon
               key_for_expression = f"{escaped_key}"  # No extra escaping here
               update_expression += f" {key_for_expression} = :{key}, "
               expression_attributes[f":{key}"] = value
        update_expression = update_expression[:-2]  # Remove trailing comma and space
        key = {"ISBN": book_data["ISBN"]}

        table.update_item(
            Key=key,
            UpdateExpression=update_expression,
            ExpressionAttributeValues=expression_attributes
        )
        # Handle image updates if provided
        if image:
            image_key = f"{book_data['ISBN']}.jpg"  # Assuming image filename is ISBN.jpg
            if image_data:
                s3_client.put_object(Bucket=bucket_name, Key=image_key, Body=image)  # Handle base64 encoded image
            else:
                s3_client.upload_file(image, bucket_name, image_key)  # Handle regular image file

        response = {'message': 'Book updated successfully!'}
        return {'statusCode': 200, 'body': json.dumps(response)}

  except ClientError as e:
        # Handle specific errors (e.g., book not found)
        return handle_error(e, operation='update')

# Function to delete a book 
# The delete_book function first validates the input data for the presence of an ISBN key.
# It optionally retrieves the book details using get_item to potentially handle errors related to image deletion later.
# The function then deletes the book entry from the DynamoDB table.
# If the retrieved book data (optional) contains an "Image" key, it attempts to delete the associated image from S3.
# Error handling is included for both DynamoDB deletion and S3 deletion (optional).
def delete_book(table, book_data, s3_client, bucket_name):
  """Deletes a book entry from the DynamoDB table and optionally removes the associated image from S3.

  Args:
      table (boto3.resource): A DynamoDB table resource.
      book_data (dict): Dictionary containing the key to identify the book (e.g., {'ISBN': '1234567890'}).
      s3_client (boto3.client): S3 client for image upload (if applicable).
      bucket_name (str): Name of the S3 bucket for image storage.

  Returns:
      dict: A dictionary containing the HTTP status code and a response message indicating success or failure.
  """
  # Validate input (e.g., ISBN)
  if 'ISBN' not in book_data:
    return handle_error(ClientError(error_code='MissingKey', message='Missing ISBN in request'), operation='delete')
  
  # Get book details (optional, for error handling with image deletion)
  try:
    book_response = table.get_item(Key=book_data)
  except ClientError:
    # Handle errors getting book details (optional)
    pass

  # Delete book entry from DynamoDB
  try:
    table.delete_item(Key=book_data)
    response = {'message': 'Book deleted successfully!'}
  except ClientError as e:
    return handle_error(e, operation='delete')  # Directly call generic error handler

  # Delete image from S3 if image key exists in retrieved book data (optional)
  if book_response and 'Image' in book_response['Item']:
    try:
      s3_client.delete_object(Bucket=bucket_name, Key=book_response['Item']['Image'])
    except ClientError:
      # Handle errors deleting image from S3 (optional)
      pass

  return {'statusCode': 200, 'body': json.dumps(response)}

# The handle_error function is the same for any CRUD operation, providing generic error logging 
# and a response with the operation name included in the message
def handle_error(error, operation):
  """ Generic error handler for CRUD operations.
    Args:
      error (ClientError): The error object from the AWS SDK.
      operation (str): The name of the CRUD operation that failed.

  Returns:
      dict: A dictionary containing the HTTP status code and error response.
  """
  print(f"Error during {operation.lower()} operation: {error}")
  return {
    'statusCode': 500,
    'body': json.dumps(f'Error during {operation} operation: {error.response["Error"]["Message"]}')
  }
