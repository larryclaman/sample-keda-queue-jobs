import os
import time
from azure.storage.queue import QueueClient

try:
  connection_string = os.environ['AzureWebJobsStorage']
  queue_name = os.environ['QUEUE_NAME']
except KeyError:
  print('Error: missing environment variable AzureWebJobsStorage or QUEUE_NAME')
  exit(1)

try:
  work_time = int(os.environ['WorkTime'])
except:
  work_time = 30

queue = QueueClient.from_connection_string(conn_str=connection_string, queue_name=queue_name)


# Get a single message
try:
  message = next(queue.receive_messages())
except:
  props = queue.get_queue_properties()
  if (props.approximate_message_count == 0):
    print("queue empty")
    exit(0)
  else:
    print("error")
    exit(1)


# Print the message
print(message)

# Delete message from the queue
queue.delete_message(message)

# Sleep for a while, simulating a long-running job
time.sleep(work_time)
