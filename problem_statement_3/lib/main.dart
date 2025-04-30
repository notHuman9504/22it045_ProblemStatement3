import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(
    ChangeNotifierProvider(
      create: (context) => TodoModel(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Modern Todo List',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          secondary: const Color(0xFF625B71),
        ),
        useMaterial3: true,
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: const Color(0xFFF7F2FA),
        ),
      ),
      home: const TodoList(),
    );
  }
}

// Todo item model
class Todo {
  final String id;
  String title;
  bool completed;
  DateTime createdAt;

  Todo({
    required this.id,
    required this.title,
    this.completed = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Convert Todo to a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'completed': completed,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  // Create a Todo from a Firestore snapshot
  factory Todo.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Todo(
      id: doc.id,
      title: data['title'] ?? '',
      completed: data['completed'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

// Provider for state management with Firestore and local fallback
class TodoModel extends ChangeNotifier {
  final List<Todo> _todos = [];
  final _uuid = const Uuid();
  final CollectionReference _todosCollection = FirebaseFirestore.instance.collection('todos');
  bool _isLoading = true;
  String? _error;
  bool _useLocalStorage = false; // Flag to use local storage instead of Firestore

  List<Todo> get todos => List.from(_todos);
  bool get isLoading => _isLoading;
  String? get error => _error;

  TodoModel() {
    _fetchTodos();
  }

  // Fetch todos from Firestore
  Future<void> _fetchTodos() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (!_useLocalStorage) {
        final QuerySnapshot snapshot = await _todosCollection.orderBy('createdAt', descending: true).get();
        _todos.clear();
        for (var doc in snapshot.docs) {
          _todos.add(Todo.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>));
        }
        _error = null;
        startListening(); // Start real-time listener
      }
    } catch (e) {
      print('Failed to load todos: $e');
      _error = 'Failed to load todos: $e';
      _useLocalStorage = true; // Fall back to local storage
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Listen to real-time updates
  void startListening() {
    if (_useLocalStorage) return; // Don't listen if using local storage
    
    try {
      _todosCollection.orderBy('createdAt', descending: true).snapshots().listen((snapshot) {
        _todos.clear();
        for (var doc in snapshot.docs) {
          _todos.add(Todo.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>));
        }
        notifyListeners();
      }, onError: (e) {
        print('Error listening to todos: $e');
        _error = 'Error listening to todos: $e';
        _useLocalStorage = true; // Fall back to local storage
        notifyListeners();
      });
    } catch (e) {
      print('Failed to set up listener: $e');
      _useLocalStorage = true; // Fall back to local storage
      notifyListeners();
    }
  }

  // Add a todo to Firestore or local storage
  Future<void> addTodo(String title) async {
    if (title.trim().isNotEmpty) {
      final newTodo = Todo(
        id: _uuid.v4(),
        title: title.trim(),
      );
      
      if (!_useLocalStorage) {
        try {
          await _todosCollection.doc(newTodo.id).set(newTodo.toMap());
          // No need to update local list as the listener will handle it
        } catch (e) {
          print('Failed to add todo to Firestore: $e');
          _useLocalStorage = true; // Fall back to local storage
          _todos.add(newTodo); // Add to local list instead
          notifyListeners();
        }
      } else {
        // Add to local list only
        _todos.add(newTodo);
        notifyListeners();
      }
    }
  }

  // Toggle todo completion status
  Future<void> toggleTodo(String id) async {
    final todoIndex = _todos.indexWhere((todo) => todo.id == id);
    if (todoIndex >= 0) {
      if (!_useLocalStorage) {
        try {
          final bool newStatus = !_todos[todoIndex].completed;
          await _todosCollection.doc(id).update({'completed': newStatus});
          // No need to update local list as the listener will handle it
        } catch (e) {
          print('Failed to update todo in Firestore: $e');
          _useLocalStorage = true; // Fall back to local storage
          _todos[todoIndex].completed = !_todos[todoIndex].completed;
          notifyListeners();
        }
      } else {
        // Update local list only
        _todos[todoIndex].completed = !_todos[todoIndex].completed;
        notifyListeners();
      }
    }
  }

  // Edit a todo
  Future<void> editTodo(String id, String newTitle) async {
    if (newTitle.trim().isNotEmpty) {
      final todoIndex = _todos.indexWhere((todo) => todo.id == id);
      if (todoIndex >= 0) {
        if (!_useLocalStorage) {
          try {
            await _todosCollection.doc(id).update({'title': newTitle.trim()});
            // No need to update local list as the listener will handle it
          } catch (e) {
            print('Failed to edit todo in Firestore: $e');
            _useLocalStorage = true; // Fall back to local storage
            _todos[todoIndex].title = newTitle.trim();
            notifyListeners();
          }
        } else {
          // Update local list only
          _todos[todoIndex].title = newTitle.trim();
          notifyListeners();
        }
      }
    }
  }

  // Delete a todo
  Future<void> deleteTodo(String id) async {
    if (!_useLocalStorage) {
      try {
        await _todosCollection.doc(id).delete();
        // No need to update local list as the listener will handle it
      } catch (e) {
        print('Failed to delete todo from Firestore: $e');
        _useLocalStorage = true; // Fall back to local storage
        _todos.removeWhere((todo) => todo.id == id);
        notifyListeners();
      }
    } else {
      // Update local list only
      _todos.removeWhere((todo) => todo.id == id);
      notifyListeners();
    }
  }
}

// Main TodoList screen
class TodoList extends StatefulWidget {
  const TodoList({super.key});

  @override
  State<TodoList> createState() => _TodoListState();
}

class _TodoListState extends State<TodoList> {
  @override
  void initState() {
    super.initState();
    // Start listening to Firestore updates
    Future.microtask(() {
      Provider.of<TodoModel>(context, listen: false).startListening();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Modern Todo List',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          const AddTodoForm(),
          Consumer<TodoModel>(
            builder: (context, todoModel, child) {
              if (todoModel.error != null) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  color: Colors.orange.shade100,
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Using local storage (Firebase error: ${todoModel.error})',
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Consumer<TodoModel>(
              builder: (context, todoModel, child) {
                // Show loading indicator
                if (todoModel.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                // Show empty state
                if (todoModel.todos.isEmpty) {
                  return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.task_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No tasks yet. Add one!',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                
                // Show the list of todos
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: todoModel.todos.length,
                  itemBuilder: (context, index) {
                    final todo = todoModel.todos[index];
                    return TodoItem(todo: todo, index: index + 1);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Form for adding new todos
class AddTodoForm extends StatefulWidget {
  const AddTodoForm({super.key});

  @override
  State<AddTodoForm> createState() => _AddTodoFormState();
}

class _AddTodoFormState extends State<AddTodoForm> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  
  bool _isListening = false;
  bool _isContinuousListening = false;
  String _lastWords = '';
  String _rawRecognizedWords = '';
  bool _speechAvailable = false;
  bool _isRecordingTodo = false;
  String _statusText = '';
  
  // Operation mode
  String _currentMode = 'none'; // 'none', 'add', 'delete'

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();
  }

  // Initialize text-to-speech
  void _initTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
  }

  // Speak feedback to the user
  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  // Initialize speech recognition
  void _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        print('Speech recognition status: $status');
        if (status == 'done' || status == 'notListening') {
          if (mounted) {
            setState(() {
              _isListening = false;
            });
          }
        }
      },
      onError: (error) {
        print('Speech recognition error: $error');
        setState(() {
          _isListening = false;
          _statusText = 'Speech recognition error. Please try again.';
        });
      },
    );
    setState(() {});
  }

  // Start listening for add todo
  void _startListeningForAddTodo() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition not available on this device'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isListening = true;
      _currentMode = 'add';
      _lastWords = '';
      _rawRecognizedWords = '';
      _statusText = 'Speak your task...';
    });

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _rawRecognizedWords = result.recognizedWords;
          _lastWords = result.recognizedWords;
          _controller.text = _lastWords;
        });
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      localeId: 'en_US',
      cancelOnError: false,
    );
  }

  // Start listening for delete todo
  void _startListeningForDeleteTodo() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition not available on this device'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final todoModel = Provider.of<TodoModel>(context, listen: false);
    if (todoModel.todos.isEmpty) {
      _speak('There are no todos to delete');
      setState(() {
        _statusText = 'There are no todos to delete';
      });
      return;
    }

    setState(() {
      _isListening = true;
      _currentMode = 'delete';
      _lastWords = '';
      _rawRecognizedWords = '';
      _statusText = 'Say the number of the task to delete... For numbers like "123", only "3" will be used.';
    });
    
    // Provide voice guidance
    _speak('Which task number would you like to delete? For multi-digit numbers, only the last digits will be used.');

    await _speech.listen(
      onResult: (result) {
        print("Speech result: '${result.recognizedWords}', Final: ${result.finalResult}");
        
        if (result.recognizedWords.isEmpty && !result.finalResult) {
          // Don't update UI for empty partial results
          return;
        }
        
        setState(() {
          _rawRecognizedWords = result.recognizedWords;
          _lastWords = result.recognizedWords;
          
          // For very short utterances, try to process immediately if it looks like a number
          if (result.finalResult && _isSingleNumber(result.recognizedWords)) {
            _processDeleteCommand(result.recognizedWords);
            _speech.stop();
            _isListening = false;
          }
        });
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      listenMode: stt.ListenMode.confirmation, // This mode is better for single words/numbers
      localeId: 'en_US',
      cancelOnError: false,
    );
  }
  
  // Check if the input is likely a single number
  bool _isSingleNumber(String input) {
    // Remove any spaces
    final trimmed = input.trim();
    
    // Check if it's a digit
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      // If it's a multi-digit number, we need to apply our trimming logic
      if (trimmed.length > 2) {
        // After trimming the first two digits, we should still have digits left
        return trimmed.length > 2;
      }
      return true;
    }
    
    // Check if it's a number word
    const numberWords = ['one', 'two', 'three', 'four', 'five', 
                        'six', 'seven', 'eight', 'nine', 'ten',
                        'first', 'second', 'third', 'fourth', 'fifth',
                        'sixth', 'seventh', 'eighth', 'ninth', 'tenth'];
    
    if (numberWords.contains(trimmed.toLowerCase())) {
      return true;
    }
    
    return false;
  }

  // Process the delete command
  void _processDeleteCommand(String command) {
    // Clean up the command for better number recognition
    String cleanCommand = command.toLowerCase()
        .replaceAll('delete', '')
        .replaceAll('number', '')
        .replaceAll('task', '')
        .replaceAll('todo', '')
        .replaceAll('item', '')
        .replaceAll('the', '')
        .trim();
    
    print('Processing delete command: "$command"');
    print('Cleaned command: "$cleanCommand"');
    
    // Try multiple regex patterns to extract the number
    int? taskNumber;
    
    // Pattern 1: Try extracting any standalone number
    final RegExp digitRegex = RegExp(r'\b(\d+)\b');
    final matches = digitRegex.allMatches(cleanCommand);
    
    if (matches.isNotEmpty) {
      // Extract the first number found
      String extracted = matches.first.group(1)!;
      
      // Trim the first two digits if there are enough digits
      if (extracted.length > 2) {
        extracted = extracted.substring(2);
      }
      
      taskNumber = int.tryParse(extracted);
      print('Extracted number after trimming: $extracted');
    }
    
    // Pattern 2: If no number found, try number words (one, two, etc.)
    if (taskNumber == null) {
      final Map<String, int> numberWords = {
        'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
        'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
        'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5,
        'sixth': 6, 'seventh': 7, 'eighth': 8, 'ninth': 9, 'tenth': 10,
      };
      
      for (final entry in numberWords.entries) {
        if (cleanCommand.contains(entry.key)) {
          taskNumber = entry.value;
          break;
        }
      }
    }
    
    // Pattern 3: Last resort, try to find any digit in the string
    if (taskNumber == null) {
      final anyDigitRegex = RegExp(r'(\d+)');
      final anyDigitMatch = anyDigitRegex.firstMatch(command);
      if (anyDigitMatch != null) {
        // Extract the number
        String extracted = anyDigitMatch.group(1)!;
        
        // Trim the first two digits if there are enough digits
        if (extracted.length > 2) {
          extracted = extracted.substring(2);
        }
        
        taskNumber = int.tryParse(extracted);
        print('Last resort extracted number after trimming: $extracted');
      }
    }
    
    // If a number was found
    if (taskNumber != null) {
      final todoModel = Provider.of<TodoModel>(context, listen: false);
      final int index = taskNumber - 1; // Convert to 0-based index
      
      if (index >= 0 && index < todoModel.todos.length) {
        final todoToDelete = todoModel.todos[index];
        todoModel.deleteTodo(todoToDelete.id);
        _speak('Deleted todo number $taskNumber');
        
        setState(() {
          _statusText = 'Deleted todo #$taskNumber';
          _currentMode = 'none';
        });
      } else {
        _speak('Invalid todo number. Please try again.');
        setState(() {
          _statusText = 'Invalid todo number $taskNumber. Valid range is 1 to ${todoModel.todos.length}';
        });
      }
    } else {
      _speak('No number detected. Please try again.');
      setState(() {
        _statusText = 'No number detected in "$command". Please say a number clearly.';
      });
    }
  }

  // Stop listening
  void _stopListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() {
        _isListening = false;
      });
      
      // Process the result based on the current mode
      if (_currentMode == 'delete' && _lastWords.isNotEmpty) {
        _processDeleteCommand(_lastWords);
      }
      
      _currentMode = 'none';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _speech.stop();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_controller.text.trim().isNotEmpty && !_isSubmitting) {
      setState(() {
        _isSubmitting = true;
      });
      
      try {
        final todoModel = Provider.of<TodoModel>(context, listen: false);
        await todoModel.addTodo(_controller.text);
        _controller.clear();
        _speak('Task added successfully');
      } catch (e) {
        // Handle error if needed
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final todoModel = Provider.of<TodoModel>(context);
    
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            offset: const Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: _isListening 
                      ? (_currentMode == 'add' ? 'Listening for task...' : 'Listening for number...') 
                      : 'Add a new task...',
                    hintStyle: TextStyle(
                      color: _isListening ? Colors.green.shade400 : Colors.grey.shade400,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _controller.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onSubmitted: (_) => _handleSubmit(),
                  enabled: !_isSubmitting && _currentMode != 'delete',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              // Add task with voice button
              Container(
                decoration: BoxDecoration(
                  color: _isListening && _currentMode == 'add'
                      ? Colors.green.shade400
                      : Theme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: _isListening 
                      ? _stopListening 
                      : _speechAvailable ? _startListeningForAddTodo : null,
                  icon: Icon(
                    _isListening && _currentMode == 'add' ? Icons.stop : Icons.mic,
                  ),
                  color: Colors.white,
                  tooltip: _isListening && _currentMode == 'add'
                      ? 'Stop recording'
                      : 'Add task with voice',
                ),
              ),
              const SizedBox(width: 12),
              // Delete task with voice button
              Container(
                decoration: BoxDecoration(
                  color: _isListening && _currentMode == 'delete'
                      ? Colors.red.shade400
                      : Colors.red.shade300,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: _isListening 
                      ? _stopListening 
                      : _speechAvailable ? _startListeningForDeleteTodo : null,
                  icon: Icon(
                    _isListening && _currentMode == 'delete' 
                        ? Icons.stop 
                        : Icons.delete_outline,
                  ),
                  color: Colors.white,
                  tooltip: _isListening && _currentMode == 'delete'
                      ? 'Stop recording'
                      : 'Delete task with voice',
                ),
              ),
              const SizedBox(width: 12),
              // Add task button
              Container(
                decoration: BoxDecoration(
                  color: _controller.text.trim().isNotEmpty
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: _isSubmitting || _controller.text.trim().isEmpty
                      ? null
                      : _handleSubmit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.add_rounded),
                  color: Colors.white,
                  iconSize: 28,
                  tooltip: 'Add Task',
                ),
              ),
            ],
          ),
          if (_statusText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                _statusText,
                style: TextStyle(
                  color: _currentMode == 'delete'
                      ? Colors.red.shade700
                      : (_isListening ? Colors.green.shade700 : Colors.grey.shade600),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          // Show task numbers when in delete mode
          if (_currentMode == 'delete' && todoModel.todos.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available task numbers:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(
                      todoModel.todos.length, 
                      (index) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Display the raw speech recognition text
          if (_isListening && _rawRecognizedWords.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Speech recognized:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
            Text(
                    _rawRecognizedWords,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Individual todo item
class TodoItem extends StatefulWidget {
  final Todo todo;
  final int index;

  const TodoItem({super.key, required this.todo, required this.index});

  @override
  State<TodoItem> createState() => _TodoItemState();
}

class _TodoItemState extends State<TodoItem> {
  bool _isDeleting = false;
  bool _isUpdating = false;

  Future<bool?> _showDeleteConfirmation(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${widget.todo.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDelete() async {
    final shouldDelete = await _showDeleteConfirmation(context);
    if (shouldDelete == true && context.mounted && !_isDeleting) {
      setState(() {
        _isDeleting = true;
      });

      try {
        await Provider.of<TodoModel>(context, listen: false).deleteTodo(widget.todo.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Task "${widget.todo.title}" deleted'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              action: SnackBarAction(
                label: 'UNDO',
                textColor: Colors.white,
                onPressed: () {
                  Provider.of<TodoModel>(context, listen: false).addTodo(widget.todo.title);
                },
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete task: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isDeleting = false;
          });
        }
      }
    }
  }

  Future<void> _handleToggle() async {
    if (!_isUpdating) {
      setState(() {
        _isUpdating = true;
      });
      
      try {
        await Provider.of<TodoModel>(context, listen: false).toggleTodo(widget.todo.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update task: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isUpdating = false;
          });
        }
      }
    }
  }

  void _showEditDialog(BuildContext context) {
    final textController = TextEditingController(text: widget.todo.title);
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Task'),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(
              hintText: 'Update task...',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            enabled: !isSubmitting,
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSubmitting ? null : () async {
                if (textController.text.trim().isNotEmpty) {
                  setDialogState(() {
                    isSubmitting = true;
                  });
                  
                  try {
                    await Provider.of<TodoModel>(context, listen: false)
                        .editTodo(widget.todo.id, textController.text);
                    if (context.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to update task: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      setDialogState(() {
                        isSubmitting = false;
                      });
                    }
                  }
                }
              },
              child: isSubmitting 
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(widget.todo.id),
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(
          Icons.delete_outline,
          color: Colors.red.shade700,
        ),
      ),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) => _showDeleteConfirmation(context),
      onDismissed: (direction) async {
        await Provider.of<TodoModel>(context, listen: false).deleteTodo(widget.todo.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Task "${widget.todo.title}" deleted'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              action: SnackBarAction(
                label: 'UNDO',
                textColor: Colors.white,
                onPressed: () {
                  Provider.of<TodoModel>(context, listen: false).addTodo(widget.todo.title);
                },
              ),
            ),
          );
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Task number indicator
              Container(
                margin: const EdgeInsets.only(right: 8),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${widget.index}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              _isUpdating
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Transform.scale(
                    scale: 1.2,
                    child: Checkbox(
                      value: widget.todo.completed,
                      onChanged: (bool? value) => _handleToggle(),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      activeColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
            ],
          ),
          title: Text(
            widget.todo.title,
            style: TextStyle(
              fontSize: 16,
              decoration:
                  widget.todo.completed ? TextDecoration.lineThrough : TextDecoration.none,
              color: widget.todo.completed ? Colors.grey : Colors.black87,
              fontWeight: widget.todo.completed ? FontWeight.normal : FontWeight.w500,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: _isDeleting ? null : () => _showEditDialog(context),
                tooltip: 'Edit Task',
              ),
              IconButton(
                icon: _isDeleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                        ),
                      )
                    : Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade400,
                      ),
                onPressed: _isDeleting ? null : _handleDelete,
                tooltip: 'Delete Task',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
