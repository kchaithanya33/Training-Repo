# What is ActiveMQ?

ActiveMQ is a message broker that sits between a Producer and a Consumer.

Its job is to:
- Receive messages from producers
- Store them safely in a queue/topic
- Deliver them to consumers
- Ensure messages are not lost if consumers are slow or temporarily down

## Why Do We Need It?

Imagine an attendance system.

### Without ActiveMQ

```
Camera
   ↓
Attendance Service
   ↓
Database
```

When a student enters:
- Camera detects face.
- Attendance Service processes it.
- Attendance is saved in the database.

**Problem:**
Camera → Attendance Service → Database

What if:
- Database is down?
- Attendance Service crashes?
- 1000 students enter at the same time?

The camera may fail to send data and attendance could be lost.

### With ActiveMQ

```
Camera
   ↓
ActiveMQ Queue
   ↓
Attendance Service
   ↓
Database
```

#### Step 1: Producer sends a message
The camera detects a student:

```json
{
  "student_id": "S101",
  "time": "09:00"
}
```

The camera sends this message to ActiveMQ.
The camera's job is done.

#### Step 2: ActiveMQ stores the message
**Queue:**
```
--------------------------------
S101 @ 09:00
--------------------------------
```

Now even if the Attendance Service is down:
Attendance Service ❌

the message remains safely stored.

#### Step 3: Consumer becomes available
After some time:
Attendance Service ✅

ActiveMQ delivers the message.

```
S101 @ 09:00
```

Attendance Service:
- Reads message
- Saves attendance
- Sends ACK (Acknowledgement)

#### Step 4: Message removed
After successful processing:
- ACK received
- ActiveMQ removes the message from the queue.

**Queue:**
```
Empty
```
