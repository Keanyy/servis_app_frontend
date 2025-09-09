import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const ServisApp());
}

class ServisApp extends StatelessWidget {
  const ServisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teknik Servis',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DeviceListScreen(),
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
  List devices = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchDevices();
  }

  Future<void> fetchDevices({String? searchQuery}) async {
    String url = "http://127.0.0.1:5000/devices";
    if (searchQuery != null && searchQuery.length >= 3) {
      url += "?q=$searchQuery";
    }
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        setState(() {
          devices = json.decode(response.body);
        });
      }
    } catch (e) {
      // Hata yönetimi
      debugPrint("API'ye baðlanýrken hata oluþtu: $e");
      // Ýsteðe baðlý olarak kullanýcýya bir mesaj gösterilebilir
    }
  }

  void openAddForm() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => AddDeviceForm(onSaved: fetchDevices)),
    );
  }

  @override
  Widget build(BuildContext context) {
    double toplamMaliyet =
        devices.fold(0, (sum, d) => sum + (d['maliyet'] ?? 0));
    double toplamServis =
        devices.fold(0, (sum, d) => sum + (d['servis_ucreti'] ?? 0));
    double netGelir = toplamServis - toplamMaliyet;

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
          onChanged: (value) {
            fetchDevices(searchQuery: value);
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => fetchDevices(searchQuery: _searchController.text),
              child: ListView.builder(
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final d = devices[index];
                  return ListTile(
                    title: Text("${d['marka']} ${d['model']}"),
                    subtitle: Text("Arýza: ${d['ariza']}"),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              DeviceDetailScreen(deviceId: d['id']),
                        ),
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
                    Text("Toplam Maliyet: $toplamMaliyet"),
                    Text("Toplam Servis Ücreti: $toplamServis"),
                    Text("Net Gelir: $netGelir"),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: openAddForm,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ---------------- Add Device Form ----------------
class AddDeviceForm extends StatefulWidget {
  final Function() onSaved;
  const AddDeviceForm({super.key, required this.onSaved});

  @override
  State<AddDeviceForm> createState() => _AddDeviceFormState();
}

class _AddDeviceFormState extends State<AddDeviceForm> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> formData = {
    'marka': '',
    'model': '',
    'seri_no': '',
    'kurum': '',
    'alinma_tarihi': '',
    'aksesuar': '',
    'ariza': '',
    'tespit': '',
    'personel': '',
    'maliyet': 0.0,
    'servis_ucreti': 0.0
  };

  Future<void> saveDevice() async {
    final response = await http.post(
      Uri.parse("http://127.0.0.1:5000/devices"),
      headers: {"Content-Type": "application/json"},
      body: json.encode(formData),
    );
    if (response.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cihaz baþarýyla eklendi')),
      );
      widget.onSaved();
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cihaz eklenirken bir hata oluþtu')),
      );
    }
  }

  Widget buildTextField(String label, String key, {bool isNumeric = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: TextEditingController(text: formData[key]),
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
                setState(() {
                  formData[key] = pickedDate.toIso8601String().substring(0, 10);
                });
              }
            },
          ),
        ),
        readOnly: true,
        onSaved: (value) {
          formData[key] = value;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Yeni Cihaz Ekle"),
      ),
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
              buildDatePickerField("Alýnma Tarihi", "alinma_tarihi"),
              buildTextField("Aksesuar", "aksesuar"),
              buildTextField("Arýza", "ariza"),
              buildTextField("Servis Tespiti", "tespit"),
              buildTextField("Ýlgili Personel", "personel"),
              buildTextField("Maliyet", "maliyet", isNumeric: true),
              buildTextField("Servis Ücreti", "servis_ucreti", isNumeric: true),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _formKey.currentState!.save();
                  saveDevice();
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
  String? imagePath1, imagePath2, imagePath3, repairImagePath1, repairImagePath2, repairImagePath3;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    fetchDevice();
  }

  Future<void> fetchDevice() async {
    final response = await http.get(
        Uri.parse("http://127.0.0.1:5000/devices/${widget.deviceId}"));
    if (response.statusCode == 200) {
      setState(() {
        device = json.decode(response.body);
        isLoading = false;
        imagePath1 = device['resim1'];
        imagePath2 = device['resim2'];
        imagePath3 = device['resim3'];
        repairImagePath1 = device['onarim_resim1'];
        repairImagePath2 = device['onarim_resim2'];
        repairImagePath3 = device['onarim_resim3'];
      });
    }
  }

  Future<void> deleteDevice() async {
    final response = await http.delete(
        Uri.parse("http://127.0.0.1:5000/devices/${widget.deviceId}"));
    if (response.statusCode == 200) {
      Navigator.pop(context);
    }
  }

  Future<void> _pickImage(int index, bool isRepair) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
      await uploadImage(index, isRepair);
    }
  }

  Future<void> uploadImage(int index, bool isRepair) async {
    if (_selectedImage == null) return;
    String url =
        "http://127.0.0.1:5000/devices/${widget.deviceId}/upload";
    var request = http.MultipartRequest('POST', Uri.parse(url));
    request.fields['index'] = isRepair ? (index + 3).toString() : index.toString();
    request.files.add(
        await http.MultipartFile.fromPath('file', _selectedImage!.path));

    final response = await request.send();
    if (response.statusCode == 200) {
      debugPrint("Resim baþarýyla yüklendi");
      fetchDevice();
    } else {
      debugPrint("Resim yüklenirken hata oluþtu");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
            "${device['marka']} ${device['model']} Detay"),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => EditDeviceForm(deviceId: widget.deviceId)),
              );
              fetchDevice();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text("Silme Onayý"),
                    content: const Text(
                        "Bu cihazý silmek istediðinizden emin misiniz?"),
                    actions: [
                      TextButton(
                        child: const Text("Hayýr"),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      TextButton(
                        child: const Text("Evet"),
                        onPressed: () {
                          deleteDevice();
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ...device.entries.where((entry) => entry.key != 'id').map((entry) {
              if (entry.key.startsWith('resim') || entry.key.startsWith('onarim_resim')) {
                return const SizedBox.shrink(); // Hide image paths
              }
              return ListTile(
                title: Text(entry.key.toUpperCase()),
                subtitle: Text(entry.value.toString()),
              );
            }).toList(),
            const SizedBox(height: 20),
            const Text("Cihaz Resimleri", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                buildImageContainer(imagePath1, 1, false),
                buildImageContainer(imagePath2, 2, false),
                buildImageContainer(imagePath3, 3, false),
              ],
            ),
            const SizedBox(height: 20),
            const Text("Onarým Sonrasý Resimler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                buildImageContainer(repairImagePath1, 1, true),
                buildImageContainer(repairImagePath2, 2, true),
                buildImageContainer(repairImagePath3, 3, true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildImageContainer(String? imagePath, int index, bool isRepair) {
    return InkWell(
      onTap: () => _pickImage(index, isRepair),
      child: Card(
        child: imagePath != null
            ? Image.network("http://127.0.0.1:5000/$imagePath", fit: BoxFit.cover)
            : const Center(child: Icon(Icons.add_a_photo)),
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
  Map<String, dynamic> formData = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchDeviceData();
  }

  Future<void> fetchDeviceData() async {
    final response = await http.get(
        Uri.parse("http://127.0.0.1:5000/devices/${widget.deviceId}"));
    if (response.statusCode == 200) {
      setState(() {
        formData = json.decode(response.body);
        isLoading = false;
      });
    }
  }

  Future<void> updateDevice() async {
    final response = await http.put(
      Uri.parse("http://127.0.0.1:5000/devices/${widget.deviceId}"),
      headers: {"Content-Type": "application/json"},
      body: json.encode(formData),
    );
    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cihaz baþarýyla güncellendi')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cihaz güncellenirken bir hata oluþtu')),
      );
    }
  }

  Widget buildTextField(String label, String key, {bool isNumeric = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        initialValue: formData[key]?.toString(),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        initialValue: formData[key],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              DateTime? pickedDate = await showDatePicker(
                context: context,
                initialDate: formData[key] != null
                    ? DateTime.tryParse(formData[key]) ?? DateTime.now()
                    : DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2101),
              );
              if (pickedDate != null) {
                setState(() {
                  formData[key] = pickedDate.toIso8601String().substring(0, 10);
                });
              }
            },
          ),
        ),
        readOnly: true,
        onSaved: (value) {
          formData[key] = value;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text("${formData['marka']} ${formData['model']} Düzenle")),
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
              buildDatePickerField("Alýnma Tarihi", "alinma_tarihi"),
              buildTextField("Aksesuar", "aksesuar"),
              buildTextField("Arýza", "ariza"),
              buildTextField("Servis Tespiti", "tespit"),
              buildDatePickerField("Geri Teslim Tarihi", "geri_teslim_tarihi"),
              buildTextField("Ýlgili Personel", "personel"),
              buildTextField("Maliyet", "maliyet", isNumeric: true),
              buildTextField("Servis Ücreti", "servis_ucreti", isNumeric: true),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _formKey.currentState!.save();
                  updateDevice();
                },
                child: const Text("Güncelle"),
              )
            ],
          ),
        ),
      ),
    );
  }
}
