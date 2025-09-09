import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// YENÝ EKLENEN IMPORT'LAR
import 'package:camera_windows/camera_windows.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// --- Global Variables & Constants ---
const String apiUrl = "http://127.0.0.1:5000";
String? _token;
String? _userRole;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && Platform.isWindows) {
    CameraWindows.registerWith();
  }

  SharedPreferences prefs = await SharedPreferences.getInstance();
  _token = prefs.getString('token');

  Widget initialScreen = const LoginScreen();
  if (_token != null && !JwtDecoder.isExpired(_token!)) {
    _userRole = JwtDecoder.decode(_token!)['role'];
    initialScreen = const DeviceListScreen();
  }

  runApp(ServisApp(initialScreen: initialScreen));
}

class ServisApp extends StatelessWidget {
  final Widget initialScreen;
  const ServisApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teknik Servis',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: initialScreen,
    );
  }
}

// --- Secure HTTP Client with UTF-8 FIX ---
class ApiClient {
  static Future<Map<String, String>> getHeaders() async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  static http.Response _processResponse(http.Response response) {
    final String decodedBody = utf8.decode(response.bodyBytes);
    return http.Response(decodedBody, response.statusCode,
        headers: response.headers);
  }

  static Future<http.Response> get(String endpoint) async {
    final response = await http.get(Uri.parse('$apiUrl$endpoint'),
        headers: await getHeaders());
    return _processResponse(response);
  }

  static Future<http.Response> post(String endpoint, {Object? body}) async {
    final response = await http.post(Uri.parse('$apiUrl$endpoint'),
        headers: await getHeaders(), body: jsonEncode(body));
    return _processResponse(response);
  }

  static Future<http.Response> put(String endpoint, {Object? body}) async {
    final response = await http.put(Uri.parse('$apiUrl$endpoint'),
        headers: await getHeaders(), body: jsonEncode(body));
    return _processResponse(response);
  }

  static Future<http.Response> delete(String endpoint) async {
    final response = await http.delete(Uri.parse('$apiUrl$endpoint'),
        headers: await getHeaders());
    return _processResponse(response);
  }
}

// ---------------- Login Screen ----------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanýcý adý ve þifre boþ olamaz')));
      return;
    }
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("$apiUrl/login"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          'username': _usernameController.text,
          'password': _passwordController.text
        }),
      );

      if (response.statusCode == 200) {
        final token = json.decode(response.body)['access_token'];
        _token = token;
        _userRole = JwtDecoder.decode(token)['role'];

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);

        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const DeviceListScreen()));
      } else {
        final error = json.decode(response.body)['error'] ?? 'Giriþ yapýlamadý';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sunucuya baðlanýlamadý')));
    } finally {
      if(mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Giriþ Yap')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Kullanýcý Adý')),
            const SizedBox(height: 16),
            TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Þifre')),
            const SizedBox(height: 24),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(onPressed: _login, child: const Text('Giriþ Yap')),
          ],
        ),
      ),
    );
  }
}


// ---------------- User Management (UNCHANGED) ----------------
class User {
  final int id;
  final String username;
  final String role;

  User({required this.id, required this.username, required this.role});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      role: json['role'],
    );
  }
}

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<User> users = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchUsers();
  }

  Future<void> fetchUsers() async {
    try {
      final response = await ApiClient.get("/users");
      if (response.statusCode == 200) {
        setState(() {
          users = (json.decode(response.body) as List)
              .map((data) => User.fromJson(data))
              .toList();
          isLoading = false;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanýcýlar yüklenirken hata oluþtu')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sunucuya baðlanýrken hata oluþtu')),
      );
    }
  }

  Future<void> addUser(String username, String password, String role) async {
    try {
      final response = await ApiClient.post("/users", body: {
        'username': username,
        'password': password,
        'role': role,
      });
      
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanýcý baþarýyla eklendi')),
        );
        fetchUsers();
      } else {
        final error = json.decode(response.body)['error'] ?? 'Kullanýcý eklenirken hata oluþtu';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sunucuya baðlanýrken hata oluþtu')),
      );
    }
  }

  Future<void> deleteUser(int userId) async {
    try {
      final response = await ApiClient.delete("/users/$userId");
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanýcý baþarýyla silindi')),
        );
        fetchUsers();
      } else {
        final error = json.decode(response.body)['error'] ?? 'Kullanýcý silinirken hata oluþtu';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sunucuya baðlanýrken hata oluþtu')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userRole != 'admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Kullanýcý Yönetimi')),
        body: const Center(child: Text('Bu sayfaya eriþim izniniz yok')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Kullanýcý Yönetimi')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return ListTile(
                  title: Text(user.username),
                  subtitle: Text(user.role),
                  trailing: user.username != 'admin'
                      ? IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Silme Onayý"),
                                content: Text("${user.username} kullanýcýsýný silmek istediðinizden emin misiniz?"),
                                actions: [
                                  TextButton(child: const Text("Hayýr"), onPressed: () => Navigator.of(ctx).pop()),
                                  TextButton(child: const Text("Evet, Sil"), onPressed: () {
                                    Navigator.of(ctx).pop();
                                    deleteUser(user.id);
                                  }),
                                ],
                              ),
                            );
                          },
                        )
                      : null,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AddUserDialog(onAdd: addUser),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
class AddUserDialog extends StatefulWidget {
  final Function(String, String, String) onAdd;
  const AddUserDialog({super.key, required this.onAdd});

  @override
  State<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<AddUserDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = 'user';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yeni Kullanýcý Ekle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Kullanýcý Adý'),
          ),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Þifre'),
          ),
          DropdownButtonFormField(
            value: _selectedRole,
            items: ['user', 'admin']
                .map((role) => DropdownMenuItem(
                      value: role,
                      child: Text(role == 'admin' ? 'Yönetici' : 'Kullanýcý'),
                    ))
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedRole = value!;
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Ýptal'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kullanýcý adý ve þifre boþ olamaz')),
              );
              return;
            }
            
            widget.onAdd(
              _usernameController.text,
              _passwordController.text,
              _selectedRole,
            );
            Navigator.pop(context);
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
// ---------------- Device List Screen ----------------
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});
  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  List? devices;
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchDevices();
  }

  Future<void> _logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    _token = null;
    _userRole = null;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()));
  }

  Future<void> fetchDevices({String? searchQuery}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    String url = "/devices";
    if (searchQuery != null && searchQuery.length >= 3) {
      url += "?q=$searchQuery";
    }
    try {
      final response = await ApiClient.get(url);
      if (response.statusCode == 200) {
        if(mounted) setState(() => devices = json.decode(response.body));
      } else {
         if(mounted) setState(
            () => _error = "Veriler yüklenemedi. Hata kodu: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("API'ye baðlanýrken hata oluþtu: $e");
       if(mounted) setState(() => _error =
          "Sunucuya baðlanýrken bir hata oluþtu. Lütfen baðlantýnýzý kontrol edin.");
    } finally {
       if(mounted) setState(() => _isLoading = false);
    }
  }

  void openAddForm() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (context) => AddDeviceForm()));
    fetchDevices();
  }

  void openUserManagement() {
    Navigator.push(context,
        MaterialPageRoute(builder: (context) => const UserManagementScreen()));
  }

  void openReportScreen() {
    Navigator.push(
        context, MaterialPageRoute(builder: (context) => const ReportScreen()));
  }

  @override
  Widget build(BuildContext context) {
    double toplamMaliyet = 0.0;
    double toplamServis = 0.0;
    double netGelir = 0.0;
    if (devices != null) {
      toplamMaliyet =
          devices!.fold(0.0, (sum, d) => sum + (d['maliyet'] ?? 0.0));
      toplamServis =
          devices!.fold(0.0, (sum, d) => sum + (d['servis_ucreti'] ?? 0.0));
      netGelir = toplamServis - toplamMaliyet;
    }

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: "Cihaz Ara...",
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                fetchDevices();
              },
            ),
          ),
          onChanged: (value) => fetchDevices(searchQuery: value),
        ),
        actions: [
          if (_userRole == 'admin')
            IconButton(
              icon: const Icon(Icons.analytics),
              onPressed: openReportScreen,
              tooltip: 'Raporlar',
            ),
          if (_userRole == 'admin')
            IconButton(
              icon: const Icon(Icons.people),
              onPressed: openUserManagement,
              tooltip: 'Kullanýcý Yönetimi',
            ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(_error!, textAlign: TextAlign.center)))
                    : RefreshIndicator(
                        onRefresh: () =>
                            fetchDevices(searchQuery: _searchController.text),
                        child: ListView.builder(
                          itemCount: devices?.length ?? 0,
                          itemBuilder: (context, index) {
                            final d = devices![index];
                            final bool isCompleted = d['status'] == 'completed';
                            return ListTile(
                              leading: isCompleted
                                  ? const Icon(Icons.check_circle,
                                      color: Colors.green)
                                  : const Icon(Icons.hourglass_top),
                              title: Text("${d['marka']} ${d['model']}"),
                              subtitle: Text("Arýza: ${d['ariza']}"),
                              trailing: Text(d['teklif_durumu'] ?? 'Belirsiz'),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          DeviceDetailScreen(deviceId: d['id'])),
                                );
                                fetchDevices();
                              },
                            );
                          },
                        ),
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        "Toplam Maliyet: ${toplamMaliyet.toStringAsFixed(2)} TL"),
                    Text(
                        "Toplam Servis Ücreti: ${toplamServis.toStringAsFixed(2)} TL"),
                    Text("Net Gelir: ${netGelir.toStringAsFixed(2)} TL"),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton:
          FloatingActionButton(onPressed: openAddForm, child: const Icon(Icons.add)),
    );
  }
}

// ---------------- Device Detail Screen ----------------
class DeviceDetailScreen extends StatefulWidget {
  final int deviceId;
  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  Map<String, dynamic> device = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchDevice();
  }

  Future<void> fetchDevice() async {
    final response = await ApiClient.get("/devices/${widget.deviceId}");
    if (response.statusCode == 200) {
      if (mounted) {
        setState(() {
          device = json.decode(response.body);
          isLoading = false;
        });
      }
    }
  }

  Future<void> deleteDevice() async {
    final response = await ApiClient.delete("/devices/${widget.deviceId}");
    if (response.statusCode == 200 && mounted) Navigator.pop(context);
  }

  Future<void> completeDevice() async {
    final response = await ApiClient.post("/devices/${widget.deviceId}/complete");
    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cihaz tamamlandý olarak iþaretlendi')));
      fetchDevice();
    }
  }

  Future<void> _pickImage(int index, bool isRepair, ImageSource source) async {
    final pickedFile = await ImagePicker().pickImage(source: source);
    if (pickedFile != null) {
      await uploadImage(File(pickedFile.path), index, isRepair);
    }
  }

  void _showImageSourceActionSheet(int index, bool isRepair) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Galeriden Seç'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(index, isRepair, ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Kameradan Çek'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(index, isRepair, ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> uploadImage(File imageFile, int index, bool isRepair) async {
    var request = http.MultipartRequest(
        'POST', Uri.parse("$apiUrl/devices/${widget.deviceId}/upload"));
    request.headers['Authorization'] = 'Bearer $_token';
    request.fields['index'] =
        isRepair ? (index + 3).toString() : index.toString();
    request.files
        .add(await http.MultipartFile.fromPath('file', imageFile.path));

    final response = await request.send();
    if (response.statusCode == 200) {
      debugPrint("Resim baþarýyla yüklendi");
      fetchDevice();
    } else {
      debugPrint("Resim yüklenirken hata oluþtu: ${response.statusCode}");
    }
  }

  // DÜZELTME: PDF Ýndirme ve açma fonksiyonu Windows uyumlu hale getirildi.
  Future<void> downloadAndOpenFile(String endpoint, String filename) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$filename indiriliyor...')),
    );

    try {
      final response = await http.get(
        Uri.parse('$apiUrl$endpoint'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        Directory? dir;
        // DÜZELTME: Hangi platformda çalýþtýðýný kontrol et
        if (Platform.isAndroid) {
          // Android için izin iste
          var status = await Permission.storage.status;
          if (!status.isGranted) {
            await Permission.storage.request();
          }
          // Android'de public "Downloads" klasörünü al (Bu eski bir yöntem, ama path_provider bunu yönetir)
          dir = await getExternalStorageDirectory(); 
          // Daha iyi bir yol: /storage/emulated/0/Download
          String downloadPath = '/storage/emulated/0/Download';
          dir = Directory(downloadPath);

        } else if (Platform.isWindows) {
           // Windows için "Downloads" klasörünü al (izin gerekmez)
          dir = await getDownloadsDirectory();
        } else {
          // Diðer platformlar için (iOS, Linux, macOS) belgeler klasörünü al
          dir = await getApplicationDocumentsDirectory();
        }

        if (dir == null) {
          throw Exception("Ýndirme dizini bulunamadý.");
        }

        final filePath = '${dir.path}/$filename';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        debugPrint('PDF indirildi: $filePath');
        await OpenFile.open(filePath);

      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'PDF indirilemedi. Hata: ${response.statusCode}')),
        );
      }
    } catch (e) {
      debugPrint("PDF Ýndirme Hatasý: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF indirilirken bir hata oluþtu: $e')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final bool isCompleted = device['status'] == 'completed';
    final bool canEdit = _userRole == 'admin' || !isCompleted;

    return Scaffold(
      appBar: AppBar(
        title: Text("${device['marka']} ${device['model']} Detay"),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.picture_as_pdf),
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                  value: 'teslim_alma', child: Text('Teslim Alma Formu')),
              const PopupMenuItem(
                  value: 'teslim_etme', child: Text('Teslim Etme Formu')),
              const PopupMenuItem(value: 'teklif', child: Text('Teklif Formu')),
            ],
            onSelected: (value) {
              switch (value) {
                case 'teslim_alma':
                  downloadAndOpenFile(
                      '/devices/${widget.deviceId}/generate-teslim-alma-formu',
                      'teslim_alma_${widget.deviceId}.pdf');
                  break;
                case 'teslim_etme':
                  downloadAndOpenFile(
                      '/devices/${widget.deviceId}/generate-teslim-etme-formu',
                      'teslim_etme_${widget.deviceId}.pdf');
                  break;
                case 'teklif':
                  downloadAndOpenFile(
                      '/devices/${widget.deviceId}/generate-teklif-formu',
                      'teklif_${widget.deviceId}.pdf');
                  break;
              }
            },
          ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          EditDeviceForm(deviceId: widget.deviceId)),
                );
                fetchDevice();
              },
            ),
          if (_userRole == 'admin')
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Silme Onayý"),
                  content: const Text(
                      "Bu cihazý kalýcý olarak silmek istediðinizden emin misiniz?"),
                  actions: [
                    TextButton(
                        child: const Text("Hayýr"),
                        onPressed: () => Navigator.of(ctx).pop()),
                    TextButton(
                      child: const Text("Evet, Sil"),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        deleteDevice();
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (!isCompleted)
            IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Ýþi Tamamla"),
                  content: const Text(
                      "Bu kaydý tamamlandý olarak iþaretlemek istediðinizden emin misiniz? Bu iþlem geri alýnamaz."),
                  actions: [
                    TextButton(
                        child: const Text("Hayýr"),
                        onPressed: () => Navigator.of(ctx).pop()),
                    TextButton(
                      child: const Text("Evet, Tamamla"),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        completeDevice();
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ...device.entries
                .where((e) => e.key != 'id' && !e.key.contains('resim'))
                .map((entry) {
              return ListTile(
                title: Text(entry.key.toUpperCase().replaceAll('_', ' ')),
                subtitle: Text(entry.value?.toString() ?? 'N/A'),
              );
            }).toList(),
            const SizedBox(height: 20),
            const Text("Cihaz Resimleri",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                buildImageContainer(device['resim1'], 1, false, canEdit),
                buildImageContainer(device['resim2'], 2, false, canEdit),
                buildImageContainer(device['resim3'], 3, false, canEdit),
              ],
            ),
            const SizedBox(height: 20),
            const Text("Onarým Sonrasý Resimler",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                buildImageContainer(device['onarim_resim1'], 1, true, canEdit),
                buildImageContainer(device['onarim_resim2'], 2, true, canEdit),
                buildImageContainer(device['onarim_resim3'], 3, true, canEdit),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildImageContainer(
      String? imagePath, int index, bool isRepair, bool canEdit) {
    return InkWell(
      onTap: canEdit ? () => _showImageSourceActionSheet(index, isRepair) : null,
      child: Card(
        child: imagePath != null && imagePath.isNotEmpty
            ? Image.network("$apiUrl/$imagePath", fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.error))
            : Center(
                child: Icon(Icons.add_a_photo,
                    color: canEdit ? Colors.black : Colors.grey)),
      ),
    );
  }
}

// ---------------- Add Device Form (UNCHANGED) ----------------
class AddDeviceForm extends StatefulWidget {
  const AddDeviceForm({super.key});

  @override
  State<AddDeviceForm> createState() => _AddDeviceFormState();
}

class _AddDeviceFormState extends State<AddDeviceForm> {
  final _formKey = GlobalKey<FormState>();

  final _markaController = TextEditingController();
  final _modelController = TextEditingController();
  final _seriNoController = TextEditingController();
  final _kurumController = TextEditingController();
  final _iletisimKisiController = TextEditingController();
  final _iletisimTelController = TextEditingController();
  final _alinmaTarihiController = TextEditingController();
  final _aksesuarController = TextEditingController();
  final _arizaController = TextEditingController();
  final _tespitController = TextEditingController();
  final _personelController = TextEditingController();
  final _maliyetController = TextEditingController(text: '0.0');
  final _servisUcretiController = TextEditingController(text: '0.0');

  String _teklifDurumu = 'Teklif Bekliyor';
  final List<String> _teklifDurumlari = [
    'Teklif Bekliyor', 'Teklif Verildi', 'Onaylandý', 'Reddedildi', 'Fatura Edildi'
  ];
  
  @override
  void dispose() {
    _markaController.dispose();
    _modelController.dispose();
    _seriNoController.dispose();
    _kurumController.dispose();
    _iletisimKisiController.dispose();
    _iletisimTelController.dispose();
    _alinmaTarihiController.dispose();
    _aksesuarController.dispose();
    _arizaController.dispose();
    _tespitController.dispose();
    _personelController.dispose();
    _maliyetController.dispose();
    _servisUcretiController.dispose();
    super.dispose();
  }

  Future<void> saveDevice() async {
    if (!_formKey.currentState!.validate()) return;
    
    Map<String, dynamic> formData = {
      'marka': _markaController.text,
      'model': _modelController.text,
      'seri_no': _seriNoController.text,
      'kurum': _kurumController.text,
      'iletisim_kisi': _iletisimKisiController.text,
      'iletisim_tel': _iletisimTelController.text,
      'alinma_tarihi': _alinmaTarihiController.text,
      'aksesuar': _aksesuarController.text,
      'ariza': _arizaController.text,
      'tespit': _tespitController.text,
      'personel': _personelController.text,
      'maliyet': double.tryParse(_maliyetController.text) ?? 0.0,
      'servis_ucreti': double.tryParse(_servisUcretiController.text) ?? 0.0,
      'teklif_durumu': _teklifDurumu,
    };

    final response = await ApiClient.post("/devices", body: formData);
    if (response.statusCode == 201 && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cihaz baþarýyla eklendi')));
      Navigator.pop(context);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cihaz eklenirken bir hata oluþtu')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Yeni Cihaz Ekle")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildTextField("Marka", _markaController),
              _buildTextField("Model", _modelController),
              _buildTextField("Seri No", _seriNoController),
              _buildTextField("Kurum", _kurumController),
              _buildTextField("Ýletiþim Kiþisi", _iletisimKisiController),
              _buildTextField("Ýletiþim Telefonu", _iletisimTelController),
              _buildDatePickerField("Alýnma Tarihi", _alinmaTarihiController),
              _buildTextField("Aksesuar", _aksesuarController),
              _buildTextField("Arýza", _arizaController, maxLines: 3),
              _buildTextField("Servis Tespiti", _tespitController, maxLines: 3),
              _buildTextField("Ýlgili Personel", _personelController),
              DropdownButtonFormField<String>(
                value: _teklifDurumu,
                decoration: const InputDecoration(labelText: 'Teklif Durumu', border: OutlineInputBorder()),
                items: _teklifDurumlari.map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (newValue) {
                  setState(() => _teklifDurumu = newValue!);
                },
              ),
              const SizedBox(height: 8),
              _buildTextField("Maliyet", _maliyetController, isNumeric: true),
              _buildTextField("Servis Ücreti", _servisUcretiController, isNumeric: true),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: saveDevice, child: const Text("Kaydet")),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool isNumeric = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
      ),
    );
  }

  Widget _buildDatePickerField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              DateTime? pickedDate = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2101),
              );
              if (pickedDate != null) {
                controller.text = pickedDate.toIso8601String().substring(0, 10);
              }
            },
          ),
        ),
        readOnly: true,
      ),
    );
  }
}

// ---------------- Edit Device Form (UNCHANGED) ----------------
class EditDeviceForm extends StatefulWidget {
  final int deviceId;
  const EditDeviceForm({super.key, required this.deviceId});
  @override
  State<EditDeviceForm> createState() => _EditDeviceFormState();
}

class _EditDeviceFormState extends State<EditDeviceForm> {
  final _formKey = GlobalKey<FormState>();
  bool isLoading = true;

  final _markaController = TextEditingController();
  final _modelController = TextEditingController();
  final _seriNoController = TextEditingController();
  final _kurumController = TextEditingController();
  final _iletisimKisiController = TextEditingController();
  final _iletisimTelController = TextEditingController();
  final _alinmaTarihiController = TextEditingController();
  final _aksesuarController = TextEditingController();
  final _arizaController = TextEditingController();
  final _tespitController = TextEditingController();
  final _personelController = TextEditingController();
  final _maliyetController = TextEditingController();
  final _servisUcretiController = TextEditingController();
  
  String? _teklifDurumu;
  final List<String> _teklifDurumlari = [
    'Teklif Bekliyor', 'Teklif Verildi', 'Onaylandý', 'Reddedildi', 'Fatura Edildi'
  ];

  @override
  void initState() {
    super.initState();
    fetchDeviceData();
  }

  @override
  void dispose() {
    _markaController.dispose();
    _modelController.dispose();
    _seriNoController.dispose();
    _kurumController.dispose();
    _iletisimKisiController.dispose();
    _iletisimTelController.dispose();
    _alinmaTarihiController.dispose();
    _aksesuarController.dispose();
    _arizaController.dispose();
    _tespitController.dispose();
    _personelController.dispose();
    _maliyetController.dispose();
    _servisUcretiController.dispose();
    super.dispose();
  }
  
  Future<void> fetchDeviceData() async {
    final response = await ApiClient.get("/devices/${widget.deviceId}");
    if (response.statusCode == 200 && mounted) {
      final data = json.decode(response.body);
      _markaController.text = data['marka'] ?? '';
      _modelController.text = data['model'] ?? '';
      _seriNoController.text = data['seri_no'] ?? '';
      _kurumController.text = data['kurum'] ?? '';
      _iletisimKisiController.text = data['iletisim_kisi'] ?? '';
      _iletisimTelController.text = data['iletisim_tel'] ?? '';
      _alinmaTarihiController.text = data['alinma_tarihi'] ?? '';
      _aksesuarController.text = data['aksesuar'] ?? '';
      _arizaController.text = data['ariza'] ?? '';
      _tespitController.text = data['tespit'] ?? '';
      _personelController.text = data['personel'] ?? '';
      _maliyetController.text = (data['maliyet'] ?? 0.0).toString();
      _servisUcretiController.text = (data['servis_ucreti'] ?? 0.0).toString();
      setState(() {
        _teklifDurumu = data['teklif_durumu'];
        isLoading = false;
      });
    }
  }

  Future<void> updateDevice() async {
    if (!_formKey.currentState!.validate()) return;
    
    Map<String, dynamic> formData = {
      'marka': _markaController.text,
      'model': _modelController.text,
      'seri_no': _seriNoController.text,
      'kurum': _kurumController.text,
      'iletisim_kisi': _iletisimKisiController.text,
      'iletisim_tel': _iletisimTelController.text,
      'alinma_tarihi': _alinmaTarihiController.text,
      'aksesuar': _aksesuarController.text,
      'ariza': _arizaController.text,
      'tespit': _tespitController.text,
      'personel': _personelController.text,
      'maliyet': double.tryParse(_maliyetController.text) ?? 0.0,
      'servis_ucreti': double.tryParse(_servisUcretiController.text) ?? 0.0,
      'teklif_durumu': _teklifDurumu,
    };

    final response = await ApiClient.put("/devices/${widget.deviceId}", body: formData);
    if (response.statusCode == 200 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cihaz baþarýyla güncellendi')));
      Navigator.pop(context);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cihaz güncellenirken bir hata oluþtu')));
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Cihazý Düzenle")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildTextField("Marka", _markaController),
              _buildTextField("Model", _modelController),
              _buildTextField("Seri No", _seriNoController),
              _buildTextField("Kurum", _kurumController),
              _buildTextField("Ýletiþim Kiþisi", _iletisimKisiController),
              _buildTextField("Ýletiþim Telefonu", _iletisimTelController),
              _buildDatePickerField("Alýnma Tarihi", _alinmaTarihiController),
              _buildTextField("Aksesuar", _aksesuarController),
              _buildTextField("Arýza", _arizaController, maxLines: 3),
              _buildTextField("Servis Tespiti", _tespitController, maxLines: 3),
              _buildTextField("Ýlgili Personel", _personelController),
              DropdownButtonFormField<String>(
                value: _teklifDurumu,
                decoration: const InputDecoration(labelText: 'Teklif Durumu', border: OutlineInputBorder()),
                items: _teklifDurumlari.map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (newValue) {
                  setState(() => _teklifDurumu = newValue);
                },
              ),
              const SizedBox(height: 8),
              _buildTextField("Maliyet", _maliyetController, isNumeric: true),
              _buildTextField("Servis Ücreti", _servisUcretiController, isNumeric: true),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: updateDevice, child: const Text("Güncelle")),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool isNumeric = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
      ),
    );
  }
  
  Widget _buildDatePickerField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              DateTime? pickedDate = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(controller.text) ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2101),
              );
              if (pickedDate != null) {
                controller.text = pickedDate.toIso8601String().substring(0, 10);
              }
            },
          ),
        ),
        readOnly: true,
      ),
    );
  }
}

// ---------------- Report Screen (UNCHANGED) ----------------
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  List? devices;
  bool isLoading = true;
  double toplamMaliyet = 0.0;
  double toplamServis = 0.0;
  double netGelir = 0.0;
  Map<String, double> kurumGelirleri = {};

  @override
  void initState() {
    super.initState();
    fetchDevices();
  }

  Future<void> fetchDevices() async {
    final response = await ApiClient.get("/devices");
    if (response.statusCode == 200) {
      if(mounted) {
        setState(() {
          devices = json.decode(response.body);
          calculateStats();
          isLoading = false;
        });
      }
    }
  }

  void calculateStats() {
    toplamMaliyet = 0.0;
    toplamServis = 0.0;
    netGelir = 0.0;
    kurumGelirleri = {};

    if (devices != null) {
      for (var d in devices!) {
        double maliyet = (d['maliyet'] ?? 0.0).toDouble();
        double servisUcreti = (d['servis_ucreti'] ?? 0.0).toDouble();
        String kurum = d['kurum'] ?? 'Belirtilmemiþ';

        toplamMaliyet += maliyet;
        toplamServis += servisUcreti;

        if (!kurumGelirleri.containsKey(kurum)) {
          kurumGelirleri[kurum] = 0.0;
        }
        kurumGelirleri[kurum] =
            (kurumGelirleri[kurum]! + (servisUcreti - maliyet));
      }
      netGelir = toplamServis - toplamMaliyet;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Raporlar")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Genel Ýstatistikler",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text("Toplam Cihaz Sayýsý: ${devices?.length ?? 0}"),
                    Text(
                        "Toplam Maliyet: ${toplamMaliyet.toStringAsFixed(2)} TL"),
                    Text(
                        "Toplam Servis Ücreti: ${toplamServis.toStringAsFixed(2)} TL"),
                    Text("Net Gelir: ${netGelir.toStringAsFixed(2)} TL"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text("Kurum Bazlý Gelirler",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: kurumGelirleri.length,
                itemBuilder: (context, index) {
                  String kurum = kurumGelirleri.keys.elementAt(index);
                  double gelir = kurumGelirleri[kurum]!;
                  return ListTile(
                    title: Text(kurum),
                    trailing: Text("${gelir.toStringAsFixed(2)} TL"),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}