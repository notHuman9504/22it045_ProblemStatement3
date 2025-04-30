import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
                    return TodoItem(todo: todo);
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

  @override
  void dispose() {
    _controller.dispose();
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
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Add a new task...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
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
              ),
              onSubmitted: (_) => _handleSubmit(),
              enabled: !_isSubmitting,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: _isSubmitting ? null : _handleSubmit,
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
    );
  }
}

// Individual todo item
class TodoItem extends StatefulWidget {
  final Todo todo;

  const TodoItem({super.key, required this.todo});

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
          leading: _isUpdating
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
