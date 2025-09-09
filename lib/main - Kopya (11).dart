import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
    if (_userRole == 'customer') {
      initialScreen = const CustomerHomeScreen();
    } else {
      initialScreen = const DeviceListScreen();
    }
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
    final headers = {'Content-Type': 'application/json; charset=utf-8'};
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

  // YENİ METOT: Logo yükleme için
  static Future<http.StreamedResponse> postMultipart(String endpoint,
      {required String filePath, required String fieldName}) async {
    var request = http.MultipartRequest('POST', Uri.parse('$apiUrl$endpoint'));
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
    return request.send();
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
          const SnackBar(content: Text('Kullanıcı adı ve şifre boş olamaz')));
      return;
    }
    setState(() => _isLoading = true);

    try {
      final response = await ApiClient.post(
        "/login",
        body: {
          'username': _usernameController.text,
          'password': _passwordController.text
        },
      );

      if (response.statusCode == 200) {
        final token = json.decode(response.body)['access_token'];
        _token = token;
        _userRole = JwtDecoder.decode(token)['role'];

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        
        if (!mounted) return;
        if (_userRole == 'customer') {
           Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const CustomerHomeScreen()));
        } else {
           Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const DeviceListScreen()));
        }

      } else {
        final error = json.decode(response.body)['error'] ?? 'Giriş yapılamadı';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sunucuya bağlanılamadı')));
    } finally {
      if(mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Giriş Yap')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Kullanıcı Adı')),
            const SizedBox(height: 16),
            TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Şifre')),
            const SizedBox(height: 24),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(onPressed: _login, child: const Text('Giriş Yap')),
          ],
        ),
      ),
    );
  }
}

// ---------------- User Management ----------------
class User {
  final int id;
  final String username;
  final String role;
  User({required this.id, required this.username, required this.role});
  factory User.fromJson(Map<String, dynamic> json) {
    return User(id: json['id'], username: json['username'], role: json['role']);
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
          const SnackBar(content: Text('Kullanıcılar yüklenirken hata oluştu')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sunucuya bağlanırken hata oluştu')),
      );
    }
  }

  Future<void> addUser(String username, String password, String role) async {
    try {
      final response = await ApiClient.post("/users", body: {
        'username': username, 'password': password, 'role': role,
      });
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanıcı başarıyla eklendi')),);
        fetchUsers();
      } else {
        final error = json.decode(response.body)['error'] ?? 'Kullanıcı eklenirken hata oluştu';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sunucuya bağlanırken hata oluştu')),);
    }
  }

  Future<void> deleteUser(int userId) async {
    try {
      final response = await ApiClient.delete("/users/$userId");
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanıcı başarıyla silindi')),);
        fetchUsers();
      } else {
        final error = json.decode(response.body)['error'] ?? 'Kullanıcı silinirken hata oluştu';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sunucuya bağlanırken hata oluştu')),);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userRole != 'admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Kullanıcı Yönetimi')),
        body: const Center(child: Text('Bu sayfaya erişim izniniz yok')),);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Kullanıcı Yönetimi')),
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
                            showDialog(context: context, builder: (ctx) => AlertDialog(
                                title: const Text("Silme Onayı"),
                                content: Text("${user.username} kullanıcısını silmek istediğinizden emin misiniz?"),
                                actions: [
                                  TextButton(child: const Text("Hayır"), onPressed: () => Navigator.of(ctx).pop()),
                                  TextButton(child: const Text("Evet, Sil"), onPressed: () {
                                    Navigator.of(ctx).pop();
                                    deleteUser(user.id);
                                  }),
                                ],
                              ),
                            );
                          },)
                      : null,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(context: context, builder: (context) => AddUserDialog(onAdd: addUser),);
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

  final Map<String, String> _roles = {
    'user': 'Kullanıcı',
    'admin': 'Yönetici',
    'customer': 'Müşteri',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yeni Kullanıcı Ekle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Kullanıcı Adı')),
          TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre')),
          DropdownButtonFormField<String>(
            value: _selectedRole,
            items: _roles.entries.map((entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    )).toList(),
            onChanged: (value) {
              setState(() {
                _selectedRole = value!;
              });
            },
            decoration: const InputDecoration(labelText: 'Kullanıcı Rolü'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
        ElevatedButton(
          onPressed: () {
            if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kullanıcı adı ve şifre boş olamaz')),);
              return;
            }
            widget.onAdd(_usernameController.text, _passwordController.text, _selectedRole);
            Navigator.pop(context);
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}

// ---------------- YENİ EKRAN: Müşteri Ana Ekranı ----------------
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  List? _customerDevices;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCustomerDevices();
  }

  Future<void> _fetchCustomerDevices() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiClient.get("/devices");
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _customerDevices = json.decode(response.body);
            _isLoading = false;
          });
        }
      } else {
         if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Hata: $e");
    }
  }

  Future<void> _logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    _token = null;
    _userRole = null;
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arıza Bildirimlerim'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Çıkış Yap',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchCustomerDevices,
              child: ListView.builder(
                itemCount: _customerDevices?.length ?? 0,
                itemBuilder: (context, index) {
                  final device = _customerDevices![index];
                  final bool isCompleted = device['status'] == 'completed';
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                       leading: isCompleted
                                  ? const Icon(Icons.check_circle, color: Colors.green)
                                  : const Icon(Icons.hourglass_top, color: Colors.orange),
                      title: Text("${device['marka'] ?? ''} ${device['model'] ?? ''}"),
                      subtitle: Text("Arıza: ${device['ariza'] ?? 'Belirtilmemiş'}"),
                      trailing: Text(device['teklif_durumu'] ?? 'Beklemede'),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(
            builder: (context) => const AddCustomerDeviceForm(),
          ));
          _fetchCustomerDevices();
        },
        child: const Icon(Icons.add),
        tooltip: 'Yeni Arıza Bildirimi',
      ),
    );
  }
}

// ---------------- YENİ FORM: Müşteri Cihaz Ekleme Formu ----------------
class AddCustomerDeviceForm extends StatefulWidget {
  const AddCustomerDeviceForm({super.key});
  @override
  State<AddCustomerDeviceForm> createState() => _AddCustomerDeviceFormState();
}

class _AddCustomerDeviceFormState extends State<AddCustomerDeviceForm> {
  final _formKey = GlobalKey<FormState>();
  final _markaController = TextEditingController();
  final _modelController = TextEditingController();
  final _kurumController = TextEditingController();
  final _iletisimKisiController = TextEditingController();
  final _arizaController = TextEditingController();
  bool _isSaving = false;

  Future<void> _saveDevice() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final formData = {
      'marka': _markaController.text,
      'model': _modelController.text,
      'kurum': _kurumController.text,
      'iletisim_kisi': _iletisimKisiController.text,
      'ariza': _arizaController.text,
    };

    try {
      final response = await ApiClient.post("/devices", body: formData);
      if (response.statusCode == 201) {
         if(!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Arıza bildiriminiz başarıyla oluşturuldu.')));
        Navigator.pop(context);
      } else {
        if(!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bildirim oluşturulurken bir hata oluştu.')));
      }
    } catch(e) {
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sunucu hatası. Lütfen tekrar deneyin.')));
    } finally {
      if(mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Yeni Arıza Bildirimi")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildTextField("Marka*", _markaController),
              _buildTextField("Model", _modelController, isRequired: false),
              _buildTextField("Kurum*", _kurumController),
              _buildTextField("İletişim Kurulacak Kişi*", _iletisimKisiController),
              _buildTextField("Arıza Açıklaması*", _arizaController, maxLines: 4),
              const SizedBox(height: 24),
              _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _saveDevice,
                      child: const Text("Bildirimi Gönder"),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {int maxLines = 1, bool isRequired = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        maxLines: maxLines,
        validator: (value) {
          if (isRequired && (value == null || value.isEmpty)) {
            return 'Bu alan boş bırakılamaz';
          }
          return null;
        },
      ),
    );
  }
}

// ---------------- Settings Screen (NEW) ----------------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  String? _logoPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiClient.get("/settings");
      if (response.statusCode == 200) {
        final settings = json.decode(response.body);
        _companyNameController.text = settings['firma_adi'] ?? '';
        _addressController.text = settings['adresi'] ?? '';
        _phoneController.text = settings['telefon'] ?? '';
        _emailController.text = settings['email'] ?? '';
        _logoPath = settings['logo_path'];
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ayarlar yüklenirken hata oluştu')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final response = await ApiClient.post(
        "/settings",
        body: {
          'firma_adi': _companyNameController.text,
          'adresi': _addressController.text,
          'telefon': _phoneController.text,
          'email': _emailController.text,
        },
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ayarlar başarıyla kaydedildi')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ayarlar kaydedilirken hata oluştu')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sunucuya bağlanırken hata oluştu')));
    }
  }

  Future<void> _pickAndUploadLogo() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final file = File(pickedFile.path);
    final fileName = file.path.split('/').last;
    final fileExtension = fileName.split('.').last.toLowerCase();
    
    if (fileExtension != 'jpg' && fileExtension != 'jpeg' && fileExtension != 'png') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sadece JPG ve PNG formatında logo yükleyebilirsiniz.')),
      );
      return;
    }

    try {
      var request = http.MultipartRequest('POST', Uri.parse("$apiUrl/settings"));
      request.headers['Authorization'] = 'Bearer $_token';
      request.fields['firma_adi'] = _companyNameController.text;
      request.fields['adresi'] = _addressController.text;
      request.fields['telefon'] = _phoneController.text;
      request.fields['email'] = _emailController.text;
      request.files.add(await http.MultipartFile.fromPath('logo', file.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logo başarıyla yüklendi ve ayarlar kaydedildi.')));
        _fetchSettings(); // Ayarları yenile
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logo yüklenirken bir hata oluştu.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yükleme sırasında sunucu hatası.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userRole != 'admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Ayarlar')),
        body: const Center(child: Text('Bu sayfaya erişim izniniz yok')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Firma Ayarları')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    TextFormField(
                      controller: _companyNameController,
                      decoration: const InputDecoration(labelText: 'Firma Adı'),
                      validator: (value) => value!.isEmpty ? 'Boş bırakılamaz' : null,
                    ),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(labelText: 'Adres'),
                    ),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(labelText: 'Telefon'),
                    ),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'E-posta'),
                    ),
                    const SizedBox(height: 20),
                    const Text("Logo", style: TextStyle(fontWeight: FontWeight.bold)),
                    _logoPath != null
                        ? Image.network(
                            "$apiUrl/uploads/logos/${_logoPath!.split('/').last}",
                            width: 100,
                            height: 100,
                          )
                        : const Text('Logo yüklü değil.'),
                    ElevatedButton.icon(
                      onPressed: _pickAndUploadLogo,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Logo Yükle ve Kaydet'),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _saveSettings,
                      child: const Text('Bilgileri Kaydet'),
                    ),
                  ],
                ),
              ),
            ),
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
      debugPrint("API'ye bağlanırken hata oluştu: $e");
       if(mounted) setState(() => _error =
          "Sunucuya bağlanırken bir hata oluştu. Lütfen bağlantınızı kontrol edin.");
    } finally {
       if(mounted) setState(() => _isLoading = false);
    }
  }

  void openAddForm() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (context) => const AddDeviceForm()));
    fetchDevices();
  }

  void openUserManagement() {
    Navigator.push(context,
        MaterialPageRoute(builder: (context) => const UserManagementScreen()));
  }
  
  void openSettings() {
    Navigator.push(context,
        MaterialPageRoute(builder: (context) => const SettingsScreen()));
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
              icon: const Icon(Icons.settings),
              onPressed: openSettings,
              tooltip: 'Ayarlar',
            ),
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
              tooltip: 'Kullanıcı Yönetimi',
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
                              subtitle: Text("Arıza: ${d['ariza']}"),
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
          const SnackBar(content: Text('Cihaz tamamlandı olarak işaretlendi')));
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
      debugPrint("Resim başarıyla yüklendi");
      fetchDevice();
    } else {
      debugPrint("Resim yüklenirken hata oluştu: ${response.statusCode}");
    }
  }

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
        if (Platform.isAndroid) {
          var status = await Permission.storage.status;
          if (!status.isGranted) await Permission.storage.request();
          dir = await getExternalStorageDirectory(); 
          String downloadPath = '/storage/emulated/0/Download';
          dir = Directory(downloadPath);
        } else if (Platform.isWindows) {
          dir = await getDownloadsDirectory();
        } else {
          dir = await getApplicationDocumentsDirectory();
        }
        if (dir == null) throw Exception("İndirme dizini bulunamadı.");
        
        final filePath = '${dir.path}/$filename';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        await OpenFile.open(filePath);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('PDF indirilemedi. Hata: ${response.statusCode}')),);
      }
    } catch (e) {
      debugPrint("PDF İndirme Hatası: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF indirilirken bir hata oluştu: $e')),);
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
              const PopupMenuItem(value: 'teslim_alma', child: Text('Teslim Alma Formu')),
              const PopupMenuItem(value: 'teslim_etme', child: Text('Teslim Etme Formu')),
              const PopupMenuItem(value: 'teklif', child: Text('Teklif Formu')),
            ],
            onSelected: (value) {
              switch (value) {
                case 'teslim_alma':
                  downloadAndOpenFile('/devices/${widget.deviceId}/generate-teslim-alma-formu', 'teslim_alma_${widget.deviceId}.pdf');
                  break;
                case 'teslim_etme':
                  downloadAndOpenFile('/devices/${widget.deviceId}/generate-teslim-etme-formu', 'teslim_etme_${widget.deviceId}.pdf');
                  break;
                case 'teklif':
                  downloadAndOpenFile('/devices/${widget.deviceId}/generate-teklif-formu', 'teklif_${widget.deviceId}.pdf');
                  break;
              }
            },
          ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(
                      builder: (context) => EditDeviceForm(deviceId: widget.deviceId)),);
                fetchDevice();
              },),
          if (_userRole == 'admin')
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => showDialog(context: context, builder: (ctx) => AlertDialog(
                  title: const Text("Silme Onayı"),
                  content: const Text("Bu cihazı kalıcı olarak silmek istediğinizden emin misiniz?"),
                  actions: [
                    TextButton(child: const Text("Hayır"), onPressed: () => Navigator.of(ctx).pop()),
                    TextButton(child: const Text("Evet, Sil"), onPressed: () {
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
                  title: const Text("İşi Tamamla"),
                  content: const Text("Bu kaydı tamamlandı olarak işaretlemek istediğinizden emin misiniz? Bu işlem geri alınamaz."),
                  actions: [
                    TextButton(child: const Text("Hayır"), onPressed: () => Navigator.of(ctx).pop()),
                    TextButton(child: const Text("Evet, Tamamla"), onPressed: () {
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
            const Text("Cihaz Resimleri", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            GridView.count(
              crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              children: [
                buildImageContainer(device['resim1'], 1, false, canEdit),
                buildImageContainer(device['resim2'], 2, false, canEdit),
                buildImageContainer(device['resim3'], 3, false, canEdit),
              ],
            ),
            const SizedBox(height: 20),
            const Text("Onarım Sonrası Resimler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            GridView.count(
              crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
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

  Widget buildImageContainer(String? imagePath, int index, bool isRepair, bool canEdit) {
    return InkWell(
      onTap: canEdit ? () => _showImageSourceActionSheet(index, isRepair) : null,
      child: Card(
        child: imagePath != null && imagePath.isNotEmpty
            ? Image.network("$apiUrl/$imagePath", fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.error))
            : Center(child: Icon(Icons.add_a_photo, color: canEdit ? Colors.black : Colors.grey)),
      ),
    );
  }
}

// ---------------- Add Device Form ----------------
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
  final List<String> _teklifDurumlari = ['Teklif Bekliyor', 'Teklif Verildi', 'Onaylandı', 'Reddedildi', 'Fatura Edildi'];
  
  @override
  void dispose() {
    _markaController.dispose(); _modelController.dispose(); _seriNoController.dispose();
    _kurumController.dispose(); _iletisimKisiController.dispose(); _iletisimTelController.dispose();
    _alinmaTarihiController.dispose(); _aksesuarController.dispose(); _arizaController.dispose();
    _tespitController.dispose(); _personelController.dispose(); _maliyetController.dispose();
    _servisUcretiController.dispose();
    super.dispose();
  }

  Future<void> saveDevice() async {
    if (!_formKey.currentState!.validate()) return;
    Map<String, dynamic> formData = {
      'marka': _markaController.text, 'model': _modelController.text, 'seri_no': _seriNoController.text,
      'kurum': _kurumController.text, 'iletisim_kisi': _iletisimKisiController.text, 'iletisim_tel': _iletisimTelController.text,
      'alinma_tarihi': _alinmaTarihiController.text, 'aksesuar': _aksesuarController.text, 'ariza': _arizaController.text,
      'tespit': _tespitController.text, 'personel': _personelController.text,
      'maliyet': double.tryParse(_maliyetController.text) ?? 0.0,
      'servis_ucreti': double.tryParse(_servisUcretiController.text) ?? 0.0,
      'teklif_durumu': _teklifDurumu,
    };
    final response = await ApiClient.post("/devices", body: formData);
    if (response.statusCode == 201 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz başarıyla eklendi')));
      Navigator.pop(context);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz eklenirken bir hata oluştu')));
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
              _buildTextField("Marka", _markaController), _buildTextField("Model", _modelController),
              _buildTextField("Seri No", _seriNoController), _buildTextField("Kurum", _kurumController),
              _buildTextField("İletişim Kişisi", _iletisimKisiController), _buildTextField("İletişim Telefonu", _iletisimTelController),
              _buildDatePickerField("Alınma Tarihi", _alinmaTarihiController), _buildTextField("Aksesuar", _aksesuarController),
              _buildTextField("Arıza", _arizaController, maxLines: 3), _buildTextField("Servis Tespiti", _tespitController, maxLines: 3),
              _buildTextField("İlgili Personel", _personelController),
              DropdownButtonFormField<String>(
                value: _teklifDurumu,
                decoration: const InputDecoration(labelText: 'Teklif Durumu', border: OutlineInputBorder()),
                items: _teklifDurumlari.map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (newValue) => setState(() => _teklifDurumu = newValue!),
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
          labelText: label, border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              DateTime? pickedDate = await showDatePicker(
                context: context, initialDate: DateTime.now(),
                firstDate: DateTime(2000), lastDate: DateTime(2101),
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

// ---------------- Edit Device Form ----------------
class EditDeviceForm extends StatefulWidget {
  final int deviceId;
  const EditDeviceForm({super.key, required this.deviceId});
  @override
  State<EditDeviceForm> createState() => _EditDeviceFormState();
}

class _EditDeviceFormState extends State<EditDeviceForm> {
  final _formKey = GlobalKey<FormState>();
  bool isLoading = true;
  final _markaController = TextEditingController(); final _modelController = TextEditingController();
  final _seriNoController = TextEditingController(); final _kurumController = TextEditingController();
  final _iletisimKisiController = TextEditingController(); final _iletisimTelController = TextEditingController();
  final _alinmaTarihiController = TextEditingController(); final _aksesuarController = TextEditingController();
  final _arizaController = TextEditingController(); final _tespitController = TextEditingController();
  final _personelController = TextEditingController(); final _maliyetController = TextEditingController();
  final _servisUcretiController = TextEditingController();
  String? _teklifDurumu;
  final List<String> _teklifDurumlari = ['Teklif Bekliyor', 'Teklif Verildi', 'Onaylandı', 'Reddedildi', 'Fatura Edildi'];

  @override
  void initState() {
    super.initState();
    fetchDeviceData();
  }

  @override
  void dispose() {
    _markaController.dispose(); _modelController.dispose(); _seriNoController.dispose();
    _kurumController.dispose(); _iletisimKisiController.dispose(); _iletisimTelController.dispose();
    _alinmaTarihiController.dispose(); _aksesuarController.dispose(); _arizaController.dispose();
    _tespitController.dispose(); _personelController.dispose(); _maliyetController.dispose();
    _servisUcretiController.dispose();
    super.dispose();
  }
  
  Future<void> fetchDeviceData() async {
    final response = await ApiClient.get("/devices/${widget.deviceId}");
    if (response.statusCode == 200 && mounted) {
      final data = json.decode(response.body);
      _markaController.text = data['marka'] ?? ''; _modelController.text = data['model'] ?? '';
      _seriNoController.text = data['seri_no'] ?? ''; _kurumController.text = data['kurum'] ?? '';
      _iletisimKisiController.text = data['iletisim_kisi'] ?? ''; _iletisimTelController.text = data['iletisim_tel'] ?? '';
      _alinmaTarihiController.text = data['alinma_tarihi'] ?? ''; _aksesuarController.text = data['aksesuar'] ?? '';
      _arizaController.text = data['ariza'] ?? ''; _tespitController.text = data['tespit'] ?? '';
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
      'marka': _markaController.text, 'model': _modelController.text, 'seri_no': _seriNoController.text,
      'kurum': _kurumController.text, 'iletisim_kisi': _iletisimKisiController.text, 'iletisim_tel': _iletisimTelController.text,
      'alinma_tarihi': _alinmaTarihiController.text, 'aksesuar': _aksesuarController.text, 'ariza': _arizaController.text,
      'tespit': _tespitController.text, 'personel': _personelController.text,
      'maliyet': double.tryParse(_maliyetController.text) ?? 0.0,
      'servis_ucreti': double.tryParse(_servisUcretiController.text) ?? 0.0,
      'teklif_durumu': _teklifDurumu,
    };
    final response = await ApiClient.put("/devices/${widget.deviceId}", body: formData);
    if (response.statusCode == 200 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz başarıyla güncellendi')));
      Navigator.pop(context);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz güncellenirken bir hata oluştu')));
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Cihazı Düzenle")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildTextField("Marka", _markaController), _buildTextField("Model", _modelController),
              _buildTextField("Seri No", _seriNoController), _buildTextField("Kurum", _kurumController),
              _buildTextField("İletişim Kişisi", _iletisimKisiController), _buildTextField("İletişim Telefonu", _iletisimTelController),
              _buildDatePickerField("Alınma Tarihi", _alinmaTarihiController), _buildTextField("Aksesuar", _aksesuarController),
              _buildTextField("Arıza", _arizaController, maxLines: 3), _buildTextField("Servis Tespiti", _tespitController, maxLines: 3),
              _buildTextField("İlgili Personel", _personelController),
              DropdownButtonFormField<String>(
                value: _teklifDurumu,
                decoration: const InputDecoration(labelText: 'Teklif Durumu', border: OutlineInputBorder()),
                items: _teklifDurumlari.map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (newValue) => setState(() => _teklifDurumu = newValue),
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
          labelText: label, border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              DateTime? pickedDate = await showDatePicker(
                context: context, initialDate: DateTime.tryParse(controller.text) ?? DateTime.now(),
                firstDate: DateTime(2000), lastDate: DateTime(2101),
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

// ---------------- Report Screen ----------------
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  List? devices;
  bool isLoading = true;
  double toplamMaliyet = 0.0, toplamServis = 0.0, netGelir = 0.0;
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
    toplamMaliyet = 0.0; toplamServis = 0.0; netGelir = 0.0;
    kurumGelirleri = {};
    if (devices != null) {
      for (var d in devices!) {
        double maliyet = (d['maliyet'] ?? 0.0).toDouble();
        double servisUcreti = (d['servis_ucreti'] ?? 0.0).toDouble();
        String kurum = d['kurum'] ?? 'Belirtilmemiş';
        toplamMaliyet += maliyet;
        toplamServis += servisUcreti;
        if (!kurumGelirleri.containsKey(kurum)) kurumGelirleri[kurum] = 0.0;
        kurumGelirleri[kurum] = (kurumGelirleri[kurum]! + (servisUcreti - maliyet));
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
                    const Text("Genel İstatistikler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text("Toplam Cihaz Sayısı: ${devices?.length ?? 0}"),
                    Text("Toplam Maliyet: ${toplamMaliyet.toStringAsFixed(2)} TL"),
                    Text("Toplam Servis Ücreti: ${toplamServis.toStringAsFixed(2)} TL"),
                    Text("Net Gelir: ${netGelir.toStringAsFixed(2)} TL"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text("Kurum Bazlı Gelirler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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