import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// platforma özel import
// ignore: depend_on_referenced_packages
import 'package:camera_windows/camera_windows.dart';

// YENÝ EKLENEN IMPORT'LAR
import 'package:file_picker/file_picker.dart'; // "Farklý Kaydet" için
import 'package:open_file_plus/open_file_plus.dart'; // Dosya açmak için

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
    try {
      _userRole = JwtDecoder.decode(_token!)['role'];
      initialScreen = const DeviceListScreen();
    } catch (e) {
      // Token bozuksa veya beklenmedik bir formatta ise login ekranýna yönlendir
      _token = null;
      await prefs.remove('token');
      initialScreen = const LoginScreen();
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
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: initialScreen,
    );
  }
}

// --- Secure HTTP Client with UTF-8 FIX ---
class ApiClient {
  static Future<Map<String, String>> getHeaders() async {
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  // UTF-8 sorununu çözmek için gelen yanýtý decode eden yardýmcý fonksiyon
  static http.Response _processResponse(http.Response response) {
    try {
      final String decodedBody = utf8.decode(response.bodyBytes);
      return http.Response(decodedBody, response.statusCode, headers: response.headers);
    } catch (e) {
      // Eđer decode edilemezse (örneđin binary veri ise) orijinal yanýtý döndür
      return response;
    }
  }

  static Future<http.Response> get(String endpoint) async {
    final response = await http.get(Uri.parse('$apiUrl$endpoint'), headers: await getHeaders());
    return _processResponse(response);
  }

  static Future<http.Response> post(String endpoint, {Object? body}) async {
    final response = await http.post(Uri.parse('$apiUrl$endpoint'), headers: await getHeaders(), body: jsonEncode(body));
    return _processResponse(response);
  }

  static Future<http.Response> put(String endpoint, {Object? body}) async {
    final response = await http.put(Uri.parse('$apiUrl$endpoint'), headers: await getHeaders(), body: jsonEncode(body));
    return _processResponse(response);
  }

  static Future<http.Response> delete(String endpoint) async {
    final response = await http.delete(Uri.parse('$apiUrl$endpoint'), headers: await getHeaders());
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kullanýcý adý ve ţifre boţ olamaz')));
      return;
    }
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("$apiUrl/login"),
        headers: {"Content-Type": "application/json; charset=utf-8"},
        body: json.encode({'username': _usernameController.text, 'password': _passwordController.text}),
      );

      if (response.statusCode == 200) {
        final token = json.decode(response.body)['access_token'];
        _token = token;
        _userRole = JwtDecoder.decode(token)['role'];

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);

        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const DeviceListScreen()));
      } else {
        final error = json.decode(utf8.decode(response.bodyBytes))['error'] ?? 'Giriţ yapýlamadý';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sunucuya bađlanýlamadý: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Giriţ Yap')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Kullanýcý Adý', border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Ţifre', border: OutlineInputBorder())),
                const SizedBox(height: 24),
                _isLoading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _login, child: const Text('Giriţ Yap')),
              ],
            ),
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
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const LoginScreen()));
  }

  Future<void> fetchDevices({String? searchQuery}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    String url = "/devices";
    if (searchQuery != null && searchQuery.trim().length >= 3) {
      url += "?q=${Uri.encodeComponent(searchQuery.trim())}";
    }
    try {
      final response = await ApiClient.get(url);
      if (response.statusCode == 200) {
        if (mounted) setState(() => devices = json.decode(response.body));
      } else {
        if (mounted) setState(() => _error = "Veriler yüklenemedi. Hata kodu: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("API'ye bađlanýrken hata oluţtu: $e");
      if (mounted) setState(() => _error = "Sunucuya bađlanýrken bir hata oluţtu. Lütfen bađlantýnýzý kontrol edin.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  void openAddForm() async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => AddDeviceForm(onSaved: fetchDevices)));
    // Geri dönüldüđünde listeyi yenile
    fetchDevices(searchQuery: _searchController.text);
  }

  @override
  Widget build(BuildContext context) {
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
          IconButton(
            icon: const Icon(Icons.summarize),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ReportScreen())),
            tooltip: 'Rapor Oluştur',
          ),
          if (_userRole == 'admin')
            IconButton(
              icon: const Icon(Icons.people),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagementScreen())),
              tooltip: 'Kullanýcý Yönetimi',
            ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: () => fetchDevices(searchQuery: _searchController.text),
                  child: ListView.builder(
                    itemCount: devices?.length ?? 0,
                    itemBuilder: (context, index) {
                      final d = devices![index];
                      final bool isCompleted = d['status'] == 'completed';
                      return ListTile(
                        leading: isCompleted
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : const Icon(Icons.hourglass_top, color: Colors.orange),
                        title: Text("${d['marka']} ${d['model']}"),
                        subtitle: Text("Kurum: ${d['kurum'] ?? 'N/A'} - Arýza: ${d['ariza']}"),
                        trailing: Text(d['teklif_durumu'] ?? 'Belirsiz'),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => DeviceDetailScreen(deviceId: d['id'])),
                          );
                          fetchDevices(searchQuery: _searchController.text);
                        },
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(onPressed: openAddForm, child: const Icon(Icons.add)),
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
    if (!mounted) return;
    setState(() => isLoading = true);
    final response = await ApiClient.get("/devices/${widget.deviceId}");
    if (mounted) {
      if (response.statusCode == 200) {
        setState(() {
          device = json.decode(response.body);
          isLoading = false;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cihaz detaylarý getirilemedi: ${response.statusCode}')));
        Navigator.pop(context); // Detaylar gelmezse sayfayý kapat
      }
    }
  }

  Future<void> deleteDevice() async {
    final response = await ApiClient.delete("/devices/${widget.deviceId}");
    if (mounted) {
      if (response.statusCode == 200) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz silinemedi.')));
      }
    }
  }
  
  Future<void> completeDevice() async {
    final response = await ApiClient.post("/devices/${widget.deviceId}/complete");
    if (mounted) {
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz tamamlandý olarak iţaretlendi')));
        fetchDevice();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ýţlem tamamlanamadý.')));
      }
    }
  }

  // --- YENÝ VE ÝŢLEVSEL PDF ÝNDÝRME FONKSÝYONU ---
  Future<void> downloadPdf(String endpoint, String defaultFilename) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$defaultFilename hazýrlanýyor...')),
    );

    try {
      final response = await http.get(
        Uri.parse('$apiUrl$endpoint'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      
      if (response.statusCode == 200) {
        // 1. "Farklý Kaydet" diyalogunu aç
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'PDF Dosyasýný Kaydet',
          fileName: defaultFilename,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );

        if (outputFile != null) {
          // Eđer kullanýcý uzantý girmediyse, .pdf ekle
          if (!outputFile.toLowerCase().endsWith('.pdf')) {
            outputFile += '.pdf';
          }
          final file = File(outputFile);
          await file.writeAsBytes(response.bodyBytes);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('PDF baţarýyla kaydedildi!'),
                action: SnackBarAction(
                  label: 'AÇ',
                  onPressed: () {
                    OpenFile.open(outputFile);
                  },
                ),
              ),
            );
          }
        }
      } else {
        final error = 'PDF indirilemedi. Sunucu Hatasý: ${response.statusCode}';
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      final error = 'PDF indirilirken bir hata oluţtu: $e';
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  // --- RESÝM YÜKLEME FONKSÝYONU ---
  Future<void> uploadImage(int index) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiUrl/devices/${widget.deviceId}/upload'),
    );
    request.headers['Authorization'] = 'Bearer $_token';
    request.fields['index'] = index.toString();
    request.files.add(await http.MultipartFile.fromPath('file', image.path));

    var response = await request.send();

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Resim yüklendi')));
      fetchDevice();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Resim yüklenemedi')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final bool isCompleted = device['status'] == 'completed';
    final bool canEdit = _userRole == 'admin' || !isCompleted;

    return Scaffold(
      appBar: AppBar(
        title: Text("${device['marka']} ${device['model']}"),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "PDF Formlarý",
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(value: 'teslim_alma', child: Text('Teslim Alma Formu')),
              const PopupMenuItem(value: 'teslim_etme', child: Text('Teslim Etme Formu')),
              const PopupMenuItem(value: 'teklif', child: Text('Teklif Formu')),
            ],
            onSelected: (value) {
              switch (value) {
                case 'teslim_alma':
                  downloadPdf('/devices/${widget.deviceId}/generate-teslim-alma-formu', 'teslim_alma_${widget.deviceId}.pdf');
                  break;
                case 'teslim_etme':
                  downloadPdf('/devices/${widget.deviceId}/generate-teslim-etme-formu', 'teslim_etme_${widget.deviceId}.pdf');
                  break;
                case 'teklif':
                  downloadPdf('/devices/${widget.deviceId}/generate-teklif-formu', 'teklif_${widget.deviceId}.pdf');
                  break;
              }
            },
          ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(
                    builder: (context) => EditDeviceForm(deviceId: widget.deviceId)),
                );
                fetchDevice();
              },
            ),
          if (_userRole == 'admin')
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Silme Onayý"),
                  content: const Text("Bu cihazý kalýcý olarak silmek istediđinizden emin misiniz?"),
                  actions: [
                    TextButton(child: const Text("Hayýr"), onPressed: () => Navigator.of(ctx).pop()),
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
                  title: const Text("Ýţi Tamamla"),
                  content: const Text("Bu kaydý tamamlandý olarak iţaretlemek istediđinizden emin misiniz?"),
                  actions: [
                    TextButton(child: const Text("Hayýr"), onPressed: () => Navigator.of(ctx).pop()),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...device.entries
              .where((e) => e.key != 'id' && !e.key.contains('resim') && e.value != null && e.value.toString().isNotEmpty)
              .map((entry) {
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(entry.key.toUpperCase().replaceAll('_', ' ')),
                    subtitle: Text(entry.value.toString()),
                  ),
                );
            }).toList(),
            
            // Resim Yükleme Bölümü
            const SizedBox(height: 20),
            const Text('Resimler:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Wrap(
              children: [
                for (int i = 1; i <= 6; i++)
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: GestureDetector(
                      onTap: () => uploadImage(i),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: device['resim$i'] != null
                            ? Image.network('$apiUrl/${device['resim$i']}', fit: BoxFit.cover)
                            : const Icon(Icons.add_a_photo, size: 40),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- ADD DEVICE FORM ---
class AddDeviceForm extends StatefulWidget {
  final Function() onSaved;
  const AddDeviceForm({super.key, required this.onSaved});

  @override
  State<AddDeviceForm> createState() => _AddDeviceFormState();
}

class _AddDeviceFormState extends State<AddDeviceForm> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> formData = {
    'marka': '', 'model': '', 'seri_no': '', 'kurum': '', 
    'alinma_tarihi': DateTime.now().toIso8601String().substring(0, 10),
    'aksesuar': '', 'ariza': '', 'tespit': '', 'personel': '',
    'maliyet': 0.0, 'servis_ucreti': 0.0,
    'teklif_durumu': 'Teklif Bekliyor',
    'iletisim_kisi': '', 'iletisim_tel': ''
  };

  final List<String> _teklifDurumlari = ['Teklif Bekliyor', 'Teklif Verildi', 'Onaylandý', 'Reddedildi', 'Fatura Edildi'];

  Future<void> saveDevice() async {
    final response = await ApiClient.post("/devices", body: formData);
    if (mounted) {
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz baţarýyla eklendi')));
        widget.onSaved();
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz eklenirken bir hata oluţtu')));
      }
    }
  }

  Widget buildTextField(String label, String key, {bool isNumeric = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        maxLines: maxLines,
        onSaved: (value) {
          if (isNumeric) {
            formData[key] = double.tryParse(value ?? '0') ?? 0.0;
          } else {
            formData[key] = value;
          }
        },
      ),
    );
  }

  Widget buildDatePickerField(String label, String key) {
    // Controller'ý state içinde tanýmla
    final controller = TextEditingController(text: formData[key]);
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
                initialDate: DateTime.tryParse(formData[key] ?? '') ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2101),
              );
              if (pickedDate != null) {
                setState(() {
                   final formattedDate = pickedDate.toIso8601String().substring(0, 10);
                   formData[key] = formattedDate;
                   controller.text = formattedDate;
                });
              }
            },
          ),
        ),
        readOnly: true,
        onSaved: (value) => formData[key] = value,
      ),
    );
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
              buildTextField("Marka", "marka"),
              buildTextField("Model", "model"),
              buildTextField("Seri No", "seri_no"),
              buildTextField("Kurum", "kurum"),
              buildTextField("Ýletiţim Kiţisi", "iletisim_kisi"),
              buildTextField("Ýletiţim Telefonu", "iletisim_tel"),
              buildDatePickerField("Alýnma Tarihi", "alinma_tarihi"),
              buildTextField("Aksesuar", "aksesuar"),
              buildTextField("Arýza", 'ariza', maxLines: 3),
              buildTextField("Servis Tespiti", "tespit", maxLines: 3),
              buildTextField("Ýlgili Personel", "personel"),
              DropdownButtonFormField<String>(
                value: formData['teklif_durumu'],
                decoration: const InputDecoration(labelText: 'Teklif Durumu', border: OutlineInputBorder()),
                items: _teklifDurumlari.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setState(() {
                    formData['teklif_durumu'] = newValue;
                  });
                },
                onSaved: (value) => formData['teklif_durumu'] = value,
              ),
              const SizedBox(height: 8),
              buildTextField("Maliyet", "maliyet", isNumeric: true),
              buildTextField("Servis Ücreti", "servis_ucreti", isNumeric: true),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()){
                    _formKey.currentState!.save();
                    saveDevice();
                  }
                },
                child: const Text("Kaydet"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// --- EDIT DEVICE FORM ---
class EditDeviceForm extends StatefulWidget {
  final int deviceId;
  const EditDeviceForm({super.key, required this.deviceId});
  @override
  State<EditDeviceForm> createState() => _EditDeviceFormState();
}
class _EditDeviceFormState extends State<EditDeviceForm> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> formData = {};
  bool isLoading = true;
  final List<String> _teklifDurumlari = ['Teklif Bekliyor', 'Teklif Verildi', 'Onaylandý', 'Reddedildi', 'Fatura Edildi'];

  @override
  void initState() {
    super.initState();
    fetchDeviceData();
  }

  Future<void> fetchDeviceData() async {
    final response = await ApiClient.get("/devices/${widget.deviceId}");
    if (mounted) {
      if (response.statusCode == 200) {
        setState(() {
          formData = json.decode(response.body);
          isLoading = false;
        });
      }
    }
  }

  Future<void> updateDevice() async {
    final response = await ApiClient.put("/devices/${widget.deviceId}", body: formData);
    if (mounted) {
       if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz baţarýyla güncellendi')));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz güncellenirken bir hata oluţtu')));
      }
    }
  }

  Widget buildTextField(String label, String key, {bool isNumeric = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        initialValue: formData[key]?.toString(),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        maxLines: maxLines,
        onSaved: (value) {
          if (isNumeric) {
            formData[key] = double.tryParse(value ?? '0') ?? 0.0;
          } else {
            formData[key] = value;
          }
        },
      ),
    );
  }

  Widget buildDatePickerField(String label, String key) {
    final controller = TextEditingController(text: formData[key]);
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
                initialDate: DateTime.tryParse(formData[key] ?? '') ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2101),
              );
              if (pickedDate != null) {
                setState(() {
                  final formattedDate = pickedDate.toIso8601String().substring(0, 10);
                  formData[key] = formattedDate;
                  controller.text = formattedDate;
                });
              }
            },
          ),
        ),
        readOnly: true,
        onSaved: (value) => formData[key] = value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Cihazý Düzenle")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              buildTextField("Marka", "marka"),
              buildTextField("Model", "model"),
              buildTextField("Seri No", "seri_no"),
              buildTextField("Kurum", "kurum"),
              buildTextField("Ýletiţim Kiţisi", "iletisim_kisi"),
              buildTextField("Ýletiţim Telefonu", "iletisim_tel"),
              buildDatePickerField("Alýnma Tarihi", "alinma_tarihi"),
              buildTextField("Aksesuar", "aksesuar"),
              buildTextField("Arýza", "ariza", maxLines: 3),
              buildTextField("Servis Tespiti", "tespit", maxLines: 3),
              buildTextField("Ýlgili Personel", "personel"),
              DropdownButtonFormField<String>(
                value: formData['teklif_durumu'],
                decoration: const InputDecoration(labelText: 'Teklif Durumu', border: OutlineInputBorder()),
                items: _teklifDurumlari.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setState(() {
                    formData['teklif_durumu'] = newValue;
                  });
                },
                onSaved: (value) => formData['teklif_durumu'] = value,
              ),
              const SizedBox(height: 8),
              buildTextField("Maliyet", "maliyet", isNumeric: true),
              buildTextField("Servis Ücreti", "servis_ucreti", isNumeric: true),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()){
                    _formKey.currentState!.save();
                    updateDevice();
                  }
                },
                child: const Text("Güncelle"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// --- USER MANAGEMENT ---
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
      if (mounted) {
        if (response.statusCode == 200) {
          setState(() {
            users = (json.decode(response.body) as List)
                .map((data) => User.fromJson(data))
                .toList();
            isLoading = false;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kullanýcýlar yüklenirken hata oluţtu')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sunucuya bađlanýrken hata oluţtu')),
        );
      }
    }
  }

  Future<void> addUser(String username, String password, String role) async {
    try {
      final response = await ApiClient.post("/users", body: {
        'username': username,
        'password': password,
        'role': role,
      });
      
      if (mounted) {
        if (response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kullanýcý baţarýyla eklendi')),
          );
          fetchUsers();
        } else {
          final error = json.decode(response.body)['error'] ?? 'Kullanýcý eklenirken hata oluţtu';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sunucuya bađlanýrken hata oluţtu')),
        );
      }
    }
  }

  Future<void> deleteUser(int userId) async {
    try {
      final response = await ApiClient.delete("/users/$userId");
      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kullanýcý baţarýyla silindi')),
          );
          fetchUsers();
        } else {
          final error = json.decode(response.body)['error'] ?? 'Kullanýcý silinirken hata oluţtu';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sunucuya bađlanýrken hata oluţtu')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userRole != 'admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Kullanýcý Yönetimi')),
        body: const Center(child: Text('Bu sayfaya eriţim izniniz yok')),
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
                                content: Text("${user.username} kullanýcýsýný silmek istediđinizden emin misiniz?"),
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
            decoration: const InputDecoration(labelText: 'Ţifre'),
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
                const SnackBar(content: Text('Kullanýcý adý ve ţifre boţ olamaz')),
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

// ---------------- Rapor Ekranı ----------------
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  bool _isLoading = false;

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _generateReport() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('$apiUrl/report?start_date=${_startDate.toIso8601String().substring(0,10)}&end_date=${_endDate.toIso8601String().substring(0,10)}'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        // PDF'i kaydet
        final String fileName = 'rapor_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final String? outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Raporu Kaydet',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );

        if (outputPath != null) {
          final File file = File(outputPath);
          await file.writeAsBytes(response.bodyBytes);
          OpenFile.open(outputPath);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rapor başarıyla oluşturuldu ve kaydedildi.')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rapor oluşturulamadı: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rapor oluşturulamadı: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rapor Oluştur')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ListTile(
              title: const Text('Başlangıç Tarihi'),
              subtitle: Text('${_startDate.day}/${_startDate.month}/${_startDate.year}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _selectDate(context, true),
            ),
            ListTile(
              title: const Text('Bitiş Tarihi'),
              subtitle: Text('${_endDate.day}/${_endDate.month}/${_endDate.year}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _selectDate(context, false),
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _generateReport,
                    child: const Text('Rapor Oluştur'),
                  ),
          ],
        ),
      ),
    );
  }
}